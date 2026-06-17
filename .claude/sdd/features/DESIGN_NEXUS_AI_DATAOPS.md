# DESIGN: NEXUS AI DataOps — Enterprise AI Command Center em Snowflake

> Arquitetura técnica completa do produto: Native App + Streamlit + Cortex Agents + dbt + Snowpark ML, 100% dentro do perímetro Snowflake do cliente.

## Metadata

| Attribute | Value |
|-----------|-------|
| **Feature** | NEXUS_AI_DATAOPS |
| **Date** | 2026-06-15 |
| **Author** | design-agent |
| **DEFINE** | [DEFINE_NEXUS_AI_DATAOPS.md](./DEFINE_NEXUS_AI_DATAOPS.md) |
| **Status** | Ready for Build |

---

## Architecture Overview

```text
╔══════════════════════════════════════════════════════════════════════════════════╗
║                        NEXUS AI DataOps — Arquitetura                          ║
╠══════════════════════════════════════════════════════════════════════════════════╣
║                                                                                  ║
║  FONTES EXTERNAS          INGESTÃO               DADOS (Snowflake)              ║
║  ─────────────────        ─────────              ──────────────────             ║
║  Salesforce/CRM  ──────→  Fivetran/COPY  ──────→  RAW.*                        ║
║  Zendesk/Support ──────→  Snowpipe Stream ─────→  STD.*  (dbt staging)         ║
║  Stripe/Billing  ──────→  COPY INTO      ──────→  MART.* (dbt marts)           ║
║  Product Events  ──────→  Snowpipe Stream ─────→  AI.*   (Snowpark ML)         ║
║  PDFs/Contratos  ──────→  Stage → Task   ──────→  AI.EMBEDDINGS                ║
║                                                    AUDIT.*                      ║
║                                                                                  ║
║  ─────────────────────────────────────────────────────────────────────────────  ║
║                                                                                  ║
║  INTELIGÊNCIA (Snowflake Cortex)         UI (Streamlit in Snowflake)            ║
║  ────────────────────────────────        ──────────────────────────             ║
║  Cortex Analyst  ←── Semantic YAML       Home.py (M1 Executive)                ║
║  Cortex Search   ←── DOCUMENT_CHUNKS     Customer_360.py (M6)                  ║
║  Cortex Agents  ←─── Tools Registry  →→  AI_Chat.py (M2)                       ║
║  Document AI    ←── Stage PDFs           Documents.py (M3)                     ║
║  Snowpark ML    ←── CHURN_FEATURES        Predictions.py (M4)                  ║
║                                           Data_Quality.py (M5)                 ║
║                                           Recommendations.py                   ║
║                                           Admin.py (M8)                        ║
║                                                                                  ║
║  ─────────────────────────────────────────────────────────────────────────────  ║
║                                                                                  ║
║  GOVERNANÇA (nativa Snowflake)           DISTRIBUIÇÃO                           ║
║  ─────────────────────────────           ─────────────                          ║
║  Masking Policies (PII)                  Native App Framework                  ║
║  Row Access Policies (multi-tenant)      Snowflake Marketplace                 ║
║  Horizon Catalog (lineage)               setup_script.sql (1-click install)    ║
║  AUDIT.PROMPT_LOG (rastreabilidade)      manifest.yml (versioning)             ║
║                                                                                  ║
╚══════════════════════════════════════════════════════════════════════════════════╝
```

---

## Components

| Componente | Propósito | Tecnologia |
|-----------|-----------|------------|
| Native App Package | Distribuição e instalação no consumer | Snowflake Native App Framework |
| Streamlit UI | Interface de usuário (8 módulos) | Streamlit in Snowflake |
| Cortex Agents | Orquestração de agentes (5 agentes) | Snowflake Cortex Agents GA |
| Cortex Analyst | NL→SQL sobre dados estruturados | Cortex Analyst + Semantic Models YAML |
| Cortex Search | RAG sobre documentos e texto | Cortex Search Service |
| Document AI | Extração de campos em PDFs | `AI_EXTRACT`, `AI_SUMMARIZE`, `AI_CLASSIFY` |
| Snowpark ML | Modelos preditivos (churn, forecast, anomaly) | Snowpark ML + Model Registry |
| dbt Core | Transformações RAW → STD → MART | dbt Core (open source) via Snowpark |
| Dynamic Tables | Refresh automático incremental de MART e AI layers | Snowflake Dynamic Tables |
| Data Metric Functions | Qualidade e observabilidade de dados | Snowflake DMFs |
| Masking Policies | Redação automática de PII por role | Snowflake Column Masking |
| Row Access Policies | Isolamento multi-tenant | Snowflake RAP |
| Audit Tables | Rastreabilidade completa de interações com IA | Streams + Tasks sobre sessões Streamlit |
| Terraform Modules | IaC para ambientes dev/stage/prod | Terraform + Snowflake Provider |
| GitHub Actions | CI/CD: deploy de Native App, dbt run, testes | GitHub Actions |

---

## Key Decisions

### Decision 1: Snowflake Native App como distribuição principal

| Attribute | Value |
|-----------|-------|
| **Status** | Accepted |
| **Date** | 2026-06-15 |

**Context:** O produto precisa rodar 100% dentro do Snowflake do cliente sem mover dados para fora. A escolha do mecanismo de distribuição determina toda a arquitetura de instalação, permissões e atualização.

**Choice:** Snowflake Native App Framework com listing no Marketplace.

**Rationale:** Native App é o único mecanismo que permite ao provider distribuir código (SQL, Python, Streamlit) que roda dentro da conta do consumer, sem que o consumer precise configurar infra própria. O Marketplace elimina o canal de vendas técnico para SMB/Mid-Market.

**Alternatives Rejected:**
1. App web externo (Next.js + Vercel) — rejeitado porque dados transitariam fora do Snowflake, eliminando o diferencial central de segurança
2. Docker self-hosted — rejeitado porque exige ops do cliente e não aproveita o Marketplace

**Consequences:**
- Setup script deve solicitar grants mínimos ao consumer (princípio de least privilege)
- Atualizações de app são propagadas pelo provider sem ação do consumer (vantagem)
- Limitações do Native App Framework: provider não pode acessar dados do consumer diretamente — deve usar `REFERENCE()`

---

### Decision 2: Streamlit in Snowflake como UI (MVP)

| Attribute | Value |
|-----------|-------|
| **Status** | Accepted |
| **Date** | 2026-06-15 |

**Context:** A UI precisa ser incluída no Native App sem infra adicional. As opções são Streamlit nativo (disponível dentro do Native App) ou SPCS com container customizado.

**Choice:** Streamlit in Snowflake para o MVP; SPCS com React planejado para v2.

**Rationale:** Streamlit está disponível nativamente dentro de Native Apps, não exige provisionamento de containers, e suporta chat, tabelas, gráficos e formulários suficientes para o MVP. O time-to-market reduz 2-3 meses vs SPCS.

**Alternatives Rejected:**
1. SPCS + React — rejeitado para MVP por complexidade de build/deploy de imagem Docker; planejado para v2 quando limitações do Streamlit se tornarem bloqueantes
2. Streamlit externo (fora do Snowflake) — rejeitado porque não pode ser incluído no Native App

**Consequences:**
- UI limitada: sem SSR, sem custom React components, sem Web Workers
- Componentes Streamlit cobrem: `st.chat_message`, `st.dataframe`, `st.plotly_chart`, `st.metric`, `st.selectbox` — suficientes para MVP
- Cada página Streamlit roda em warehouse dedicado `NEXUS_UI_WH` (XS por padrão)

---

### Decision 3: Cortex Agents como runtime de agentes

| Attribute | Value |
|-----------|-------|
| **Status** | Accepted |
| **Date** | 2026-06-15 |

**Context:** O produto precisa de agentes que orquestrem dados estruturados (SQL) e não estruturados (documentos). As opções são usar o Cortex Agents GA do Snowflake ou um framework externo (LangGraph, LangChain).

**Choice:** Cortex Agents GA com tools `CORTEX_ANALYST_TEXT_TO_SQL` e `CORTEX_SEARCH_TEXT_RETRIEVAL`.

**Rationale:** Cortex Agents roda dentro do Snowflake (dados não saem), integra nativamente com Cortex Analyst e Cortex Search, e está em GA com SLA. Para casos onde Cortex Agents não suporta tool customizada, usa-se Stored Procedure Python como tool wrapper.

**Alternatives Rejected:**
1. LangGraph externo — rejeitado porque agent runtime fora do Snowflake exige que dados saiam do perímetro
2. LangChain — idem; além de overhead de infra (containers, APIs, auth)

**Consequences:**
- Tool use customizado tem limitações: usar Stored Procedures Python como wrappers quando necessário
- Modelos disponíveis via Cortex: `claude-3-5-sonnet`, `mistral-large2`, `llama3.1-70b` — sem Claude API direta
- Latência de Cortex Agents: p50 ~3-8s para perguntas simples; p95 ~15-30s para multi-step

---

### Decision 4: dbt Core + Dynamic Tables para pipeline

| Attribute | Value |
|-----------|-------|
| **Status** | Accepted |
| **Date** | 2026-06-15 |

**Context:** A pipeline de dados precisa transformar RAW → STD → MART com versionamento, testes e refresh automático.

**Choice:** dbt Core para transformações SQL versionadas (staging e marts); Dynamic Tables para refresh automático incremental nas camadas MART e AI.

**Rationale:** dbt oferece versionamento de SQL, testes de qualidade, lineage automático via `ref()`, e documentação. Dynamic Tables eliminam a necessidade de Tasks/Streams para refresh incremental de marts. A combinação cobre batch e near-real-time sem Spark ou Databricks.

**Alternatives Rejected:**
1. Streams + Tasks puro — rejeitado para transformações complexas por falta de versionamento e dificuldade de teste
2. Spark/Databricks — rejeitado por sair do ecossistema Snowflake e adicionar ops de cluster

**Consequences:**
- dbt run executa via GitHub Actions (CI/CD) ou manualmente via `NEXUS_ORCHESTRATION_WH`
- Dynamic Tables têm `TARGET_LAG` configurável: `1 hour` para MART, `30 minutes` para AI layer
- Schema changes em RAW devem ser versionados em dbt para não quebrar Dynamic Tables downstream

---

### Decision 5: Snowpark ML para modelos preditivos

| Attribute | Value |
|-----------|-------|
| **Status** | Accepted |
| **Date** | 2026-06-15 |

**Context:** O produto inclui churn score, revenue forecast e anomaly detection. Os modelos precisam ser treinados e servidos dentro do Snowflake.

**Choice:** Snowpark ML com Model Registry para treino, versionamento e serving de modelos.

**Rationale:** Snowpark ML permite treinar modelos Python (XGBoost, LightGBM, sklearn) diretamente no Snowflake usando dados do MART layer. Model Registry garante versionamento e auditoria. Inference via UDF Python ou `MODEL.RUN()` retorna scores direto em SQL — sem API externa.

**Alternatives Rejected:**
1. SageMaker / Vertex AI — rejeitados porque dados sairiam do Snowflake para treino
2. Cortex ML Functions (`FORECAST`, `DETECT_ANOMALIES`) — usados como fallback/complemento mas sem controle de feature engineering customizado

**Consequences:**
- Modelos são servidos via Snowpark UDF — latência de inference ~100-500ms por batch
- Treino agendado via Task Snowflake: semanal para churn, diário para anomaly
- Model Registry necessário para rastreabilidade de versão nos outputs de AI layer

---

## File Manifest

### Grupo 1: Native App Foundation

| # | Arquivo | Action | Propósito | Agente | Deps |
|---|---------|--------|-----------|--------|------|
| 1 | `native_app/manifest.yml` | Create | Declaração do Native App (versão, artifacts, privileges) | @snowflake-data-engineer | — |
| 2 | `native_app/setup_script.sql` | Create | Script de instalação no consumer (schemas, grants, UI) | @snowflake-data-engineer | 1 |
| 3 | `native_app/readme.md` | Create | Documentação do listing no Marketplace | @code-documenter | 1, 2 |

### Grupo 2: Snowflake DDL e Setup

| # | Arquivo | Action | Propósito | Agente | Deps |
|---|---------|--------|-----------|--------|------|
| 4 | `snowflake/setup/01_databases.sql` | Create | Criar NEXUS_APP database e schemas (CORE, RAW, STD, MART, AI, AUDIT, GOVERNANCE, CONFIG) | @snowflake-sql-expert | — |
| 5 | `snowflake/setup/02_warehouses.sql` | Create | Criar warehouses: NEXUS_UI_WH (XS), NEXUS_COMPUTE_WH (S), NEXUS_ML_WH (M), NEXUS_ORCHESTRATION_WH (XS) | @snowflake-sql-expert | — |
| 6 | `snowflake/setup/03_roles.sql` | Create | RBAC: NEXUS_ADMIN, NEXUS_ANALYST, NEXUS_VIEWER, NEXUS_DATA_ENGINEER | @snowflake-governance-expert | 4, 5 |
| 7 | `snowflake/setup/04_core_tables.sql` | Create | DDL das tabelas CORE: CUSTOMERS, PRODUCTS, TRANSACTIONS, TICKETS, INTERACTIONS, CONTRACTS, DOCUMENTS | @snowflake-sql-expert | 4, 6 |
| 8 | `snowflake/setup/05_ai_tables.sql` | Create | DDL das tabelas AI: CHURN_SCORES, RECOMMENDATIONS, AGENT_SESSIONS, AGENT_MESSAGES, DOCUMENT_CHUNKS, EMBEDDINGS | @snowflake-sql-expert | 4, 6 |
| 9 | `snowflake/setup/06_audit_tables.sql` | Create | DDL das tabelas AUDIT: PROMPT_LOG, ACCESS_LOG, ACTION_LOG, DATA_QUALITY_RESULTS | @snowflake-sql-expert | 4, 6 |
| 10 | `snowflake/setup/07_masking_policies.sql` | Create | Masking policies para PII: email, phone, ssn, credit_card — por role | @snowflake-governance-expert | 6, 7 |
| 11 | `snowflake/setup/08_row_access_policies.sql` | Create | Row access policies para multi-tenant (isolamento por org_id) | @snowflake-governance-expert | 6, 7 |
| 12 | `snowflake/setup/09_network_rules.sql` | Create | Bloquear egress para fora do Snowflake; allowlist para fontes de ingestão | @snowflake-governance-expert | — |
| 13 | `snowflake/setup/10_tasks_and_streams.sql` | Create | Tasks para: audit log, data quality checks, embedding refresh, briefing semanal | @snowflake-data-engineer | 4, 5, 9 |

### Grupo 3: Cortex AI — Semantic Models e Agents

| # | Arquivo | Action | Propósito | Agente | Deps |
|---|---------|--------|-----------|--------|------|
| 14 | `snowflake/cortex/semantic_models/customer_revenue.yaml` | Create | Semantic model para Cortex Analyst: métricas de ARR, churn, tickets, uso | @snowflake-cortex-expert | 7, 8 |
| 15 | `snowflake/cortex/semantic_models/executive_kpis.yaml` | Create | Semantic model para KPIs executivos: revenue, margin, risk, NPS | @snowflake-cortex-expert | 7 |
| 16 | `snowflake/cortex/search_services/customer_docs.sql` | Create | Cortex Search Service sobre DOCUMENT_CHUNKS para RAG em contratos e tickets | @snowflake-cortex-expert | 8 |
| 17 | `snowflake/cortex/agents/executive_agent.yaml` | Create | Agente Executive Analyst: tools=[Analyst, Search], audience=CEO/CFO/COO | @snowflake-cortex-expert | 14, 15, 16 |
| 18 | `snowflake/cortex/agents/revenue_agent.yaml` | Create | Agente Revenue: tools=[Analyst(revenue marts)], audience=CRO/Sales | @snowflake-cortex-expert | 14 |
| 19 | `snowflake/cortex/agents/customer_agent.yaml` | Create | Agente Customer Intelligence: tools=[Analyst, Search], audience=CS/CX | @snowflake-cortex-expert | 14, 16 |
| 20 | `snowflake/cortex/agents/risk_agent.yaml` | Create | Agente Risk & Compliance: tools=[Search(docs), Audit tables], audience=Legal | @snowflake-cortex-expert | 16 |
| 21 | `snowflake/cortex/agents/data_steward_agent.yaml` | Create | Agente Data Steward: tools=[DMF results, lineage, cost monitor], audience=Data Eng | @snowflake-cortex-expert | 9 |
| 22 | `snowflake/cortex/stored_procedures/tool_wrappers.sql` | Create | Python Stored Procedures como tool wrappers para Cortex Agents (CRM actions, Slack, etc.) | @snowflake-data-engineer | 4, 5 |

### Grupo 4: dbt Models

| # | Arquivo | Action | Propósito | Agente | Deps |
|---|---------|--------|-----------|--------|------|
| 23 | `dbt/dbt_project.yml` | Create | Configuração do projeto dbt (profiles, models, vars, tests) | @dbt-specialist | — |
| 24 | `dbt/profiles.yml` | Create | Conexão Snowflake (usa env vars para credenciais) | @dbt-specialist | — |
| 25 | `dbt/models/staging/stg_customers.sql` | Create | Padroniza clientes de múltiplas fontes → STD.CUSTOMERS | @dbt-specialist | 7 |
| 26 | `dbt/models/staging/stg_transactions.sql` | Create | Padroniza transações (Stripe/billing) → STD.TRANSACTIONS | @dbt-specialist | 7 |
| 27 | `dbt/models/staging/stg_tickets.sql` | Create | Padroniza tickets de suporte (Zendesk) → STD.TICKETS | @dbt-specialist | 7 |
| 28 | `dbt/models/staging/stg_contracts.sql` | Create | Padroniza contratos → STD.CONTRACTS | @dbt-specialist | 7 |
| 29 | `dbt/models/marts/customer_360.sql` | Create | Golden record de cliente: ARR, uso, tickets, NPS, score, next_action | @dbt-specialist | 25, 26, 27, 28 |
| 30 | `dbt/models/marts/revenue_daily.sql` | Create | Mart de receita diária: ARR, MRR, churn MRR, expansion MRR | @dbt-specialist | 26 |
| 31 | `dbt/models/marts/churn_features.sql` | Create | Feature store para modelo de churn (inputs do Snowpark ML) | @dbt-specialist | 29 |
| 32 | `dbt/models/marts/executive_kpis.sql` | Create | KPIs executivos agregados: receita, risco, NPS, saúde média da base | @dbt-specialist | 29, 30 |
| 33 | `dbt/models/ai/document_chunks.sql` | Create | Chunking de documentos para Cortex Search (split por parágrafo) | @dbt-specialist | 28 |
| 34 | `dbt/schema.yml` | Create | Tests dbt: not_null em PKs, unique em customer_id, accepted_values | @dbt-specialist | 25–33 |

### Grupo 5: Snowpark ML — Modelos Preditivos

| # | Arquivo | Action | Propósito | Agente | Deps |
|---|---------|--------|-----------|--------|------|
| 35 | `models/churn_model.py` | Create | Treino XGBoost para churn score + registro no Model Registry | @python-developer | 31 |
| 36 | `models/forecast_model.py` | Create | Revenue forecast com Cortex ML FORECAST (fallback: ARIMA via Snowpark) | @python-developer | 30 |
| 37 | `models/anomaly_model.py` | Create | Anomaly detection em métricas operacionais (Isolation Forest) | @python-developer | 32 |
| 38 | `models/recommendation_model.py` | Create | Next-best-action engine baseado em churn score + uso + segmento | @python-developer | 35, 29 |
| 39 | `models/embedding_pipeline.py` | Create | Gera embeddings de DOCUMENT_CHUNKS via `EMBED_TEXT_1024` para Cortex Search | @python-developer | 33 |

### Grupo 6: Pipelines de Ingestão

| # | Arquivo | Action | Propósito | Agente | Deps |
|---|---------|--------|-----------|--------|------|
| 40 | `pipelines/ingest_salesforce.py` | Create | Ingestão de Salesforce via API → RAW.SALESFORCE.* usando Snowpipe ou COPY INTO | @python-developer | 4 |
| 41 | `pipelines/ingest_zendesk.py` | Create | Ingestão de Zendesk tickets via API → RAW.ZENDESK.TICKETS | @python-developer | 4 |
| 42 | `pipelines/ingest_stripe.py` | Create | Ingestão de Stripe events via webhook → RAW.STRIPE.EVENTS via Snowpipe Streaming | @python-developer | 4 |
| 43 | `pipelines/ingest_documents.py` | Create | Upload de PDFs → Snowflake Stage → processamento com Document AI → CORE.DOCUMENTS | @python-developer | 8 |
| 44 | `pipelines/demo_data_generator.py` | Create | Gera dataset demo realista para VP1 (SaaS) — usado em Marketplace trial | @python-developer | 7, 8 |

### Grupo 7: Streamlit UI — Módulos

| # | Arquivo | Action | Propósito | Agente | Deps |
|---|---------|--------|-----------|--------|------|
| 45 | `app/streamlit/Home.py` | Create | M1: Executive Command Center — KPIs, alertas, narrativa AI, Action Center | @python-developer | 17, 32 |
| 46 | `app/streamlit/pages/2_Customer_360.py` | Create | M6: Perfil completo de cliente — timeline, score, tickets, contratos, recomendação | @python-developer | 19, 29 |
| 47 | `app/streamlit/pages/3_AI_Chat.py` | Create | M2: Chat governado — Cortex Agents com histórico, citação de fonte, SQL visível | @python-developer | 17, 18, 19 |
| 48 | `app/streamlit/pages/4_Documents.py` | Create | M3: Document Intelligence — upload PDF, extração, resumo, perguntas | @python-developer | 20, 43 |
| 49 | `app/streamlit/pages/5_Predictions.py` | Create | M4: Churn score, forecast, anomaly — com explicação de drivers e impacto $ | @python-developer | 35, 36, 37 |
| 50 | `app/streamlit/pages/6_Data_Quality.py` | Create | M5: Observabilidade — freshness, volume, schema drift, score por domínio | @python-developer | 21, 9 |
| 51 | `app/streamlit/pages/7_Recommendations.py` | Create | Action Center — fila de recomendações com prioridade e impacto financeiro | @python-developer | 38 |
| 52 | `app/streamlit/pages/8_Admin.py` | Create | M8: Governance — RBAC, audit log, cost monitor, PII discovery | @python-developer | 10, 11, 9 |
| 53 | `app/streamlit/utils/auth.py` | Create | Helpers de autenticação: get_current_role(), has_permission(), get_org_id() | @python-developer | 6 |
| 54 | `app/streamlit/utils/snowflake_client.py` | Create | Cliente Snowflake para Streamlit: execute_query(), call_cortex(), call_agent() | @python-developer | 4, 5 |
| 55 | `app/streamlit/utils/audit_logger.py` | Create | Logger de auditoria: registra prompt, resposta, fontes, user, role em AUDIT.PROMPT_LOG | @python-developer | 9 |
| 56 | `app/streamlit/config/app_config.yaml` | Create | Configurações do app: warehouses, modelos LLM, thresholds de alerta, vertical pack ativo | @python-developer | — |

### Grupo 8: IaC e CI/CD

| # | Arquivo | Action | Propósito | Agente | Deps |
|---|---------|--------|-----------|--------|------|
| 57 | `terraform/main.tf` | Create | Provider Snowflake + módulos: databases, warehouses, roles | @ci-cd-specialist | — |
| 58 | `terraform/variables.tf` | Create | Variáveis parametrizadas por ambiente (dev/stage/prod) | @ci-cd-specialist | 57 |
| 59 | `terraform/environments/dev/terraform.tfvars` | Create | Valores dev: warehouse size XS, 1 region | @ci-cd-specialist | 58 |
| 60 | `terraform/environments/prod/terraform.tfvars` | Create | Valores prod: warehouse size M, multi-region config | @ci-cd-specialist | 58 |
| 61 | `.github/workflows/ci.yml` | Create | CI: dbt test, Python lint, Snowflake SQL validation | @ci-cd-specialist | 23, 34 |
| 62 | `.github/workflows/deploy_native_app.yml` | Create | Deploy: bump version em manifest.yml, upload artifacts, publish Native App | @ci-cd-specialist | 1, 2 |
| 63 | `.github/workflows/deploy_dbt.yml` | Create | dbt run + dbt test em Snowflake (staging e prod) | @ci-cd-specialist | 23 |

### Grupo 9: Testes

| # | Arquivo | Action | Propósito | Agente | Deps |
|---|---------|--------|-----------|--------|------|
| 64 | `tests/sql/test_core_tables.sql` | Create | Validar integridade referencial, nulls em PKs, counts pós-ingestão | @snowflake-sql-expert | 7 |
| 65 | `tests/sql/test_security.sql` | Create | Validar masking (user sem role não vê PII), row access (tenant A não vê tenant B) | @snowflake-governance-expert | 10, 11 |
| 66 | `tests/python/test_churn_model.py` | Create | pytest para churn model: AUC > 0.75, feature importance, inference latency < 500ms | @python-developer | 35 |
| 67 | `tests/python/test_agents.py` | Create | Eval de agentes: 20 perguntas golden set, accuracy > 80%, latência < 15s | @python-developer | 17–21 |
| 68 | `tests/python/test_audit_logger.py` | Create | pytest para audit logger: 100% de cobertura de interações registradas | @python-developer | 55 |
| 69 | `tests/python/test_pipelines.py` | Create | pytest para pipelines de ingestão: schema validation, null checks, upsert idempotência | @python-developer | 40–43 |

**Total de Arquivos: 69**

---

## Agent Assignment Rationale

| Agente | Arquivos | Por quê |
|--------|----------|---------|
| @snowflake-data-engineer | 1, 2, 10, 11, 13, 22 | Native App setup, Tasks/Streams, DDL avançado |
| @snowflake-sql-expert | 4–9, 64 | DDL de tabelas, schemas, SQL puro sem lógica Python |
| @snowflake-governance-expert | 6, 10, 11, 12, 65 | RBAC, masking, row access, network rules |
| @snowflake-cortex-expert | 14–21, 22 | Semantic models, Cortex Agents, Search Services |
| @dbt-specialist | 23–34 | Modelos dbt, tests, staging e marts |
| @python-developer | 35–56, 66–69 | Snowpark ML, Streamlit, pipelines, utils, testes Python |
| @ci-cd-specialist | 57–63 | Terraform, GitHub Actions, deploy de Native App |
| @code-documenter | 3, 56 | README do Marketplace, config YAML documentada |

---

## Code Patterns

### Pattern 1: Cortex Analyst Query (Streamlit)

```python
# snowflake_client.py — padrão para NL→SQL via Cortex Analyst
import snowflake.snowpark as snowpark
import requests

def query_cortex_analyst(
    session: snowpark.Session,
    question: str,
    semantic_model: str = "customer_revenue",
    warehouse: str = "NEXUS_COMPUTE_WH"
) -> dict:
    """Envia pergunta ao Cortex Analyst e retorna SQL + resultado."""
    stage_path = f"@NEXUS_APP.CONFIG.SEMANTIC_MODELS/{semantic_model}.yaml"
    
    response = session.sql(f"""
        SELECT SNOWFLAKE.CORTEX.ANALYST(
            '{question}',
            PARSE_JSON('{{"semantic_model_file": "{stage_path}"}}')
        )
    """).collect()[0][0]
    
    result = json.loads(response)
    sql = result.get("sql", "")
    
    if sql:
        data = session.sql(sql).to_pandas()
        return {"sql": sql, "data": data, "explanation": result.get("explanation")}
    return {"error": result.get("message"), "sql": None, "data": None}
```

### Pattern 2: Cortex Search RAG (documentos)

```python
# Padrão RAG com Cortex Search para chat com documentos
def search_documents(
    session: snowpark.Session,
    query: str,
    search_service: str = "NEXUS_APP.AI.CUSTOMER_DOCS_SEARCH",
    limit: int = 5,
    columns: list = ["chunk_text", "document_name", "page_number"]
) -> list[dict]:
    """Recupera chunks relevantes para RAG."""
    result = session.sql(f"""
        SELECT PARSE_JSON(
            SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
                '{search_service}',
                OBJECT_CONSTRUCT(
                    'query', '{query}',
                    'columns', {json.dumps(columns)},
                    'limit', {limit}
                )::VARCHAR
            )
        ) AS search_result
    """).collect()[0][0]
    
    return json.loads(result).get("results", [])
```

### Pattern 3: Cortex Agents Tool Call

```python
# Padrão de chamada ao Cortex Agents com histórico de sessão
def call_agent(
    session: snowpark.Session,
    agent_id: str,          # ex: "executive_agent"
    user_message: str,
    session_history: list,  # list[dict] com role/content anteriores
    role: str               # role do usuário atual para auditoria
) -> dict:
    """Chama Cortex Agent e registra auditoria."""
    agent_config = load_agent_config(agent_id)  # carrega YAML do stage
    
    messages = session_history + [{"role": "user", "content": user_message}]
    
    response = session.sql(f"""
        SELECT SNOWFLAKE.CORTEX.AGENT(
            '{agent_config["model"]}',
            PARSE_JSON('{json.dumps(messages)}'),
            PARSE_JSON('{json.dumps(agent_config["tools"])}'),
            OBJECT_CONSTRUCT('temperature', 0.1, 'max_tokens', 2048)
        )
    """).collect()[0][0]
    
    result = json.loads(response)
    
    # Sempre registrar no audit log
    audit_logger.log(session, user_message, result, agent_id, role)
    
    return result
```

### Pattern 4: Masking Policy PII

```sql
-- snowflake/setup/07_masking_policies.sql
-- Email visível apenas para NEXUS_ADMIN; mascarado para demais
CREATE OR REPLACE MASKING POLICY NEXUS_APP.GOVERNANCE.MASK_EMAIL
AS (val STRING) RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('NEXUS_ADMIN', 'SYSADMIN') THEN val
        WHEN val IS NULL THEN NULL
        ELSE REGEXP_REPLACE(val, '(^[^@]{1,2})[^@]*(@.*)', '\\1***\\2')
    END;

-- Aplicar na coluna
ALTER TABLE NEXUS_APP.CORE.CUSTOMERS
    MODIFY COLUMN email
    SET MASKING POLICY NEXUS_APP.GOVERNANCE.MASK_EMAIL;
```

### Pattern 5: Dynamic Table para Customer 360

```sql
-- Refresh automático a partir do mart dbt
CREATE OR REPLACE DYNAMIC TABLE NEXUS_APP.AI.CUSTOMER_360_LIVE
    TARGET_LAG = '1 hour'
    WAREHOUSE = NEXUS_COMPUTE_WH
AS
SELECT
    c.customer_id,
    c.name,
    c.segment,
    c.arr,
    cs.churn_probability,
    cs.risk_level,
    cs.top_drivers,
    cs.recommended_action,
    c360.ticket_count_30d,
    c360.usage_trend,
    c360.nps_score,
    r.recommendation_text,
    r.expected_impact_usd
FROM NEXUS_APP.MART.CUSTOMER_360 c360
JOIN NEXUS_APP.CORE.CUSTOMERS c USING (customer_id)
LEFT JOIN NEXUS_APP.AI.CHURN_SCORES cs USING (customer_id)
LEFT JOIN NEXUS_APP.AI.RECOMMENDATIONS r
    ON r.entity_id = c.customer_id
    AND r.is_active = TRUE;
```

### Pattern 6: Snowpark ML — Churn Model

```python
# models/churn_model.py — treino e registro do modelo de churn
from snowflake.ml.modeling.xgboost import XGBClassifier
from snowflake.ml.registry import Registry
import snowflake.snowpark as snowpark

def train_churn_model(session: snowpark.Session) -> str:
    """Treina modelo de churn e registra no Model Registry."""
    features_df = session.table("NEXUS_APP.MART.CHURN_FEATURES")
    
    feature_cols = [
        "usage_trend_30d", "ticket_count_30d", "days_since_login",
        "arr", "contract_days_remaining", "nps_score", "support_sentiment_avg"
    ]
    label_col = "churned_90d"
    
    train_df, test_df = features_df.random_split([0.8, 0.2], seed=42)
    
    model = XGBClassifier(
        input_cols=feature_cols,
        label_cols=[label_col],
        output_cols=["CHURN_PROBABILITY"],
        n_estimators=200,
        max_depth=6,
        learning_rate=0.05
    )
    model.fit(train_df)
    
    # Avaliar no test set
    predictions = model.predict(test_df)
    
    # Registrar no Model Registry
    registry = Registry(session=session, database_name="NEXUS_APP", schema_name="AI")
    model_version = registry.log_model(
        model=model,
        model_name="CHURN_MODEL",
        comment=f"XGBoost churn model — features: {feature_cols}"
    )
    
    return model_version.version_name
```

### Pattern 7: Audit Logger

```python
# app/streamlit/utils/audit_logger.py
from datetime import datetime, timezone
import json
import uuid

def log_interaction(
    session,
    user_message: str,
    agent_response: dict,
    agent_id: str,
    user_role: str,
    data_sources: list[str] = None
) -> None:
    """Registra toda interação com agente no AUDIT.PROMPT_LOG."""
    log_entry = {
        "log_id": str(uuid.uuid4()),
        "session_id": st.session_state.get("session_id"),
        "user_name": session.get_current_user(),
        "role_name": user_role,
        "agent_id": agent_id,
        "prompt_text": _redact_pii(user_message),
        "data_sources": json.dumps(data_sources or []),
        "response_summary": str(agent_response.get("content", ""))[:500],
        "cortex_tokens_used": agent_response.get("usage", {}).get("total_tokens", 0),
        "latency_ms": agent_response.get("latency_ms", 0),
        "created_at": datetime.now(timezone.utc).isoformat()
    }
    
    session.sql("""
        INSERT INTO NEXUS_APP.AUDIT.PROMPT_LOG
        SELECT
            $1:log_id::VARCHAR,
            $1:session_id::VARCHAR,
            $1:user_name::VARCHAR,
            $1:role_name::VARCHAR,
            $1:agent_id::VARCHAR,
            $1:prompt_text::TEXT,
            PARSE_JSON($1:data_sources::VARCHAR),
            $1:response_summary::TEXT,
            $1:cortex_tokens_used::INTEGER,
            $1:latency_ms::INTEGER,
            $1:created_at::TIMESTAMP_TZ
        FROM VALUES (PARSE_JSON(:1))
    """, params=[json.dumps(log_entry)]).collect()
```

### Pattern 8: Streamlit Page com RBAC

```python
# app/streamlit/pages/3_AI_Chat.py — padrão de página com auth
import streamlit as st
from utils.auth import get_current_role, has_permission
from utils.snowflake_client import get_session, call_agent
from utils.audit_logger import log_interaction

def render():
    role = get_current_role()
    
    # Guard: verificar permissão mínima
    if not has_permission(role, "NEXUS_VIEWER"):
        st.error("Acesso não autorizado.")
        st.stop()
    
    # Selecionar agente baseado no role
    agent_map = {
        "NEXUS_ADMIN": "executive_agent",
        "NEXUS_ANALYST": "revenue_agent",
        "NEXUS_VIEWER": "customer_agent"
    }
    agent_id = agent_map.get(role, "customer_agent")
    
    st.title("AI Chat")
    
    if "messages" not in st.session_state:
        st.session_state.messages = []
    
    for msg in st.session_state.messages:
        with st.chat_message(msg["role"]):
            st.markdown(msg["content"])
    
    if prompt := st.chat_input("Pergunte sobre seus dados..."):
        st.session_state.messages.append({"role": "user", "content": prompt})
        
        with st.chat_message("assistant"):
            with st.spinner("Consultando agente..."):
                session = get_session()
                response = call_agent(session, agent_id, prompt,
                                      st.session_state.messages[:-1], role)
                
                answer = response.get("content", "Não foi possível responder.")
                st.markdown(answer)
                
                # Mostrar SQL gerado (se disponível)
                if sql := response.get("sql"):
                    with st.expander("SQL gerado"):
                        st.code(sql, language="sql")
        
        st.session_state.messages.append({"role": "assistant", "content": answer})

render()
```

### Pattern 9: Native App manifest.yml

```yaml
# native_app/manifest.yml
manifest_version: 1

version:
  name: "1.0.0"
  label: "NEXUS AI DataOps v1.0.0"
  comment: "Enterprise AI Command Center para Snowflake"

artifacts:
  setup_script: setup_script.sql
  readme: readme.md
  default_streamlit: app/streamlit/Home

privileges:
  - name: CREATE DATABASE
    description: "Criar database NEXUS_APP no consumer"
  - name: EXECUTE TASK
    description: "Executar tasks de audit log e data quality"
  - name: CREATE WAREHOUSE
    description: "Criar warehouses NEXUS_UI_WH, NEXUS_COMPUTE_WH, NEXUS_ML_WH"

references:
  - CUSTOMER_TABLE:
      label: "Tabela de Clientes"
      description: "Tabela principal de clientes do consumer"
      object_type: TABLE
      multi_valued: false
```

---

## Data Flow

```text
1. INGESTÃO (fontes externas → RAW)
   │  Fivetran/API → RAW.SALESFORCE.*, RAW.ZENDESK.*, RAW.STRIPE.*
   │  Snowpipe Streaming → RAW.EVENTS.PRODUCT_USAGE (near real-time)
   │  Stage + Task → RAW.DOCUMENTS.FILES (PDFs via upload Streamlit)
   ▼
2. STAGING / PADRONIZAÇÃO (RAW → STD via dbt)
   │  dbt run: stg_customers, stg_transactions, stg_tickets, stg_contracts
   │  Dynamic Table TARGET_LAG = '30 minutes' para tabelas críticas
   ▼
3. MARTS / BUSINESS LAYER (STD → MART via dbt)
   │  customer_360.sql → MART.CUSTOMER_360 (golden record)
   │  revenue_daily.sql → MART.REVENUE_DAILY
   │  churn_features.sql → MART.CHURN_FEATURES (input para ML)
   │  executive_kpis.sql → MART.EXECUTIVE_KPIS
   ▼
4. AI LAYER (MART → AI via Snowpark ML + Cortex)
   │  Task diária: churn_model.py → AI.CHURN_SCORES
   │  Task diária: forecast_model.py → AI.REVENUE_FORECAST
   │  Task diária: recommendation_model.py → AI.RECOMMENDATIONS
   │  Task 30min: embedding_pipeline.py → AI.DOCUMENT_CHUNKS + AI.EMBEDDINGS
   ▼
5. SERVING (AI + MART → Cortex Agents → Streamlit)
   │  Cortex Analyst: query semantic model → SQL → resultado
   │  Cortex Search: query DOCUMENT_CHUNKS → chunks relevantes
   │  Cortex Agent: orquestra Analyst + Search → resposta final
   ▼
6. AUDITORIA (toda interação → AUDIT)
   │  audit_logger.py registra: user, role, prompt, fontes, resposta, tokens, latência
   │  Task diária gera relatório de acesso para M8 Governance
```

---

## Integration Points

| Sistema Externo | Tipo de Integração | Autenticação | Direção |
|----------------|-------------------|--------------|---------|
| Salesforce | Fivetran → Snowpipe / COPY INTO | OAuth 2.0 via Fivetran | Entrada (RAW) |
| Zendesk | Fivetran / API REST | API Token via Secret | Entrada (RAW) |
| Stripe | Webhook → Snowpipe Streaming | Stripe webhook signature | Entrada (RAW) |
| PDFs (S3/SharePoint) | Snowflake Stage externo | Storage Integration | Entrada (Stage) |
| Slack/Teams | External Access Integration | Bot Token via Secret | Saída (M7 Automation) |
| Jira/ServiceNow | External Access Integration | API Key via Secret | Saída (M7 Automation) |
| Snowflake Marketplace | Native App Framework | Provider account | Distribuição |

> **Nota:** External Access Integrations devem ser aprovadas explicitamente pelo consumer ao instalar o Native App. Integração de saída (M7) é opcional e requer grant adicional.

---

## Testing Strategy

| Tipo | Escopo | Arquivos | Ferramentas | Meta de Cobertura |
|------|--------|----------|-------------|-------------------|
| SQL Unit | DDL, masking, row access | `tests/sql/test_*.sql` | Snowflake SQL | 100% das policies |
| Python Unit | ML models, pipelines, utils | `tests/python/test_*.py` | pytest + snowflake-snowpark-python | 80% das funções |
| dbt Tests | not_null, unique, accepted_values | `dbt/schema.yml` | dbt test | 100% das PKs e FKs |
| Agent Eval | 20 perguntas golden set por agente | `tests/python/test_agents.py` | pytest + manual eval | Accuracy > 80%, latência < 15s |
| Security | RBAC, masking, tenant isolation | `tests/sql/test_security.sql` | Snowflake SQL | 100% dos cenários de AT-003, AT-009 |
| Integration | Ingestão end-to-end | `tests/python/test_pipelines.py` | pytest + Snowflake test DB | Happy path + error path |
| Manual E2E | Fluxo demo completo (AT-001 a AT-012) | — | Manual + Streamlit | 12 acceptance tests |

---

## Error Handling

| Tipo de Erro | Estratégia | Retry? | Alerta? |
|-------------|------------|--------|---------|
| Cortex Agent timeout (> 30s) | Retornar mensagem amigável + logar em AUDIT | Não | Sim — Data Steward Agent |
| Cortex Analyst sem SQL gerado | Mostrar "Não entendi a pergunta" + sugestões | Não | Não |
| Falha em ingestão (API externa) | Task marca status=FAILED em CONFIG.INGEST_LOG; retry automático 3x | Sim — 3x com backoff | Sim — alerta no M5 |
| Dynamic Table com lag excedido | DMF de freshness dispara; alerta no M5 Data Quality | N/A | Sim |
| Model inference error (Snowpark ML) | Fallback para score médio do segmento; logar erro | Não | Sim — Data Steward Agent |
| Native App permission denied | Mostrar tela de setup com instrução de grant faltante | Não | Não (user action required) |
| PII detectado em prompt do usuário | Redact antes de registrar em AUDIT; não bloquear resposta | Não | Log apenas |
| Warehouse suspenso | Auto-resume via `AUTO_RESUME = TRUE` no warehouse | Automático | Não |

---

## Configuration

| Config Key | Tipo | Default | Descrição |
|------------|------|---------|-----------|
| `default_llm_model` | string | `claude-3-5-sonnet` | Modelo Cortex para agentes |
| `ui_warehouse` | string | `NEXUS_UI_WH` | Warehouse para Streamlit |
| `compute_warehouse` | string | `NEXUS_COMPUTE_WH` | Warehouse para queries e agentes |
| `ml_warehouse` | string | `NEXUS_ML_WH` | Warehouse para treino de modelos |
| `churn_high_threshold` | float | `0.7` | Score de churn acima = HIGH risk |
| `churn_medium_threshold` | float | `0.4` | Score acima = MEDIUM risk |
| `freshness_sla_hours` | int | `24` | Horas máximas sem refresh antes de alerta |
| `agent_max_tokens` | int | `2048` | Max tokens por resposta de agente |
| `agent_temperature` | float | `0.1` | Temperature para respostas determinísticas |
| `audit_retention_days` | int | `365` | Retenção de logs de auditoria |
| `vertical_pack` | string | `saas_customer` | Vertical Pack ativo (determina agentes e UI) |
| `enable_workflow_automation` | bool | `false` | Habilitar M7 (External Access para CRM/Slack) |
| `demo_mode` | bool | `false` | Usar dataset demo em vez de dados reais |

---

## Security Considerations

- **Zero egress de dados**: `NETWORK_RULE` bloqueia todo tráfego de saída exceto integrações explicitamente aprovadas pelo consumer via External Access Integration
- **Least privilege no Native App**: setup_script solicita apenas grants mínimos; consumer pode revogar M7 (Automation) sem impactar o restante
- **PII redaction em prompts**: audit_logger.py passa prompts por `_redact_pii()` antes de armazenar — padrão regex para email, CPF, telefone, cartão
- **Masking policies aplicadas em todas as colunas PII**: email, phone, ssn, credit_card, address — visíveis apenas para NEXUS_ADMIN
- **Row access policies para multi-tenant**: consumidores do Native App com múltiplas org_ids veem apenas seus próprios dados
- **Secret management**: credenciais de APIs externas armazenadas em `SNOWFLAKE.VAULT` (Secrets), nunca em código ou variáveis de ambiente
- **Warehouse auto-suspend**: todos os warehouses com `AUTO_SUSPEND = 60` para reduzir custo e superfície de ataque
- **Cortex Agent guardrails**: system prompt de cada agente inclui instrução para não revelar SQL interno, não executar DDL, não acessar tabelas fora do schema autorizado

---

## Observability

| Aspecto | Implementação |
|---------|---------------|
| Logging de aplicação | Streamlit: `st.session_state` + AUDIT.PROMPT_LOG; Python: structured logging via `logging` module → Snowflake Event Table |
| Métricas de qualidade de dados | Data Metric Functions (DMF) em MART e STD tables; resultados em GOVERNANCE.DATA_QUALITY_RESULTS |
| Custo por agente/usuário | Query History + AUDIT.PROMPT_LOG cruzados com `cortex_tokens_used`; visível no Admin Console (M8) |
| Latência de agentes | Registrada em AUDIT.PROMPT_LOG (`latency_ms`); alertas se p95 > 20s |
| Freshness de pipelines | DMF de freshness em tabelas críticas; alerta automático em M5 Data Quality |
| Model drift | Task semanal compara distribuição de CHURN_SCORES com baseline; alerta se drift > 15% |
| Erros de ingestão | CONFIG.INGEST_LOG com status e mensagem de erro por execução |

---

## Pipeline Architecture

### DAG de Transformação

```text
[Salesforce API]──Fivetran──→ [RAW.SALESFORCE.*]
[Zendesk API]────Fivetran──→ [RAW.ZENDESK.*]      ──dbt staging──→ [STD.*]
[Stripe Webhook]─Snowpipe──→ [RAW.STRIPE.*]                              │
[Product Events]─Snowpipe──→ [RAW.EVENTS.*]                              │
                                                                          ▼
                                                                   [MART.*] ──Snowpark ML──→ [AI.*]
                                                                   customer_360              churn_scores
                                                                   revenue_daily             recommendations
                                                                   churn_features            document_chunks
                                                                   executive_kpis            embeddings
                                                                          │
                                                    [PDFs/Docs]────Stage──→ [AI.DOCUMENT_CHUNKS]
                                                                          │
                                                                          ▼
                                                          [Cortex Search Service] ←── CUSTOMER_DOCS_SEARCH
                                                          [Cortex Analyst]        ←── SEMANTIC_MODELS/*.yaml
                                                          [Cortex Agents]         ←── agents/*.yaml
                                                                          │
                                                                          ▼
                                                                  [Streamlit UI]
                                                                          │
                                                                          ▼
                                                                  [AUDIT.PROMPT_LOG]
```

### Partition Strategy

| Tabela | Chave de Partição | Granularidade | Justificativa |
|--------|------------------|---------------|---------------|
| AUDIT.PROMPT_LOG | `created_at` | Diária | Alta inserção; queries filtradas por período |
| MART.REVENUE_DAILY | `revenue_date` | Diária | Queries sempre com filtro de data |
| AI.CHURN_SCORES | `scored_at` | Diária | Histórico de scores para tracking de drift |
| CORE.TRANSACTIONS | `transaction_date` | Mensal | Volume alto; queries por período fiscal |
| AI.DOCUMENT_CHUNKS | `document_id` | — | Acesso por documento; sem partição temporal |

### Incremental Strategy

| Modelo dbt | Estratégia | Coluna Chave | Lookback |
|------------|-----------|--------------|---------|
| `stg_customers` | `unique_key` (customer_id) | `updated_at` | — |
| `stg_transactions` | `incremental_by_time` | `transaction_date` | 3 dias |
| `stg_tickets` | `incremental_by_time` | `created_at` | 7 dias |
| `customer_360` | `unique_key` (customer_id) | `updated_at` | — |
| `revenue_daily` | `incremental_by_time` | `revenue_date` | 30 dias |
| `churn_features` | `unique_key` (customer_id) | `feature_date` | — |

### Schema Evolution Plan

| Tipo de Mudança | Tratamento | Rollback |
|----------------|------------|---------|
| Nova coluna em CORE.* | Adicionar com `DEFAULT NULL`; backfill assíncrono via Task | `ALTER TABLE DROP COLUMN` |
| Mudança de tipo | Dual-write em coluna nova por 2 semanas; depois migrar | Reativar coluna antiga |
| Remoção de coluna | Deprecar em `schema.yml` com `deprecated: true`; remover após 30 dias | Re-adicionar coluna |
| Novo campo em Semantic Model YAML | Versionado no git; teste via Cortex Analyst antes de deploy | Reverter git + redeploy |

### Data Quality Gates

| Gate | Ferramenta | Threshold | Ação em Falha |
|------|-----------|-----------|--------------|
| Null em PKs (customer_id, score_id) | dbt test `not_null` | 0 nulls | Bloquear dbt run |
| Unicidade de PKs | dbt test `unique` | 0 duplicatas | Bloquear dbt run |
| Freshness de STD.CUSTOMERS | dbt `source freshness` | < 24h | Alerta em M5 + email |
| Row count delta em MART.CUSTOMER_360 | DMF `ROW_COUNT` | < 20% variação diária | Alerta em M5 |
| Churn score em range válido [0,1] | dbt test `accepted_values` range | 100% em [0,1] | Bloquear Task de scoring |
| Cobertura de scores: 100% clientes ativos | SQL assertion em test_agents.py | 0 clientes sem score | Alerta + reprocessar |

---

## Revision History

| Versão | Data | Autor | Mudanças |
|--------|------|-------|---------|
| 1.0 | 2026-06-15 | design-agent | Versão inicial a partir de DEFINE_NEXUS_AI_DATAOPS.md |

---

## Next Step

**Ready for:** `/build .claude/sdd/features/DESIGN_NEXUS_AI_DATAOPS.md`

> O `/build` deve iniciar pelo **Grupo 1 (Native App Foundation)** e **Grupo 2 (Snowflake DDL)**, pois todos os demais grupos dependem da infraestrutura base estar criada.
>
> Ordem de build recomendada:
> 1. Grupo 2 (DDL + setup SQL) — schemas, warehouses, roles, masking
> 2. Grupo 1 (Native App manifest + setup_script)
> 3. Grupo 4 (dbt models) — depende de tabelas existirem
> 4. Grupo 3 (Cortex semantic models + agents) — depende de marts dbt
> 5. Grupo 5 (Snowpark ML) — depende de MART.CHURN_FEATURES
> 6. Grupo 6 (Pipelines de ingestão)
> 7. Grupo 7 (Streamlit UI) — depende de tudo acima
> 8. Grupo 8 (IaC + CI/CD)
> 9. Grupo 9 (Testes)
