# BRAINSTORM: NEXUS AI DataOps — Stack & Arquitetura Completa

> Exploratory session para definir a stack mínima e a arquitetura do produto completo antes de capturar requisitos formais

## Metadata

| Attribute | Value |
|-----------|-------|
| **Feature** | NEXUS_AI_DATAOPS_STACK |
| **Date** | 2026-06-15 |
| **Author** | brainstorm-agent |
| **Status** | Ready for Define |

---

## Initial Idea

**Raw Input:** Produto completo NEXUS AI DataOps — Enterprise AI Command Center nativo em Snowflake. Stack e arquitetura completa para o produto inteiro, não apenas MVP.

**Context Gathered:**
- Projeto em fase zero — único arquivo é `CONTEXT.md` com blueprint de 6.500+ linhas (exportação de sessão ChatGPT)
- Stack-alvo já definido no blueprint: Native App + Streamlit + Cortex AI/Search/Analyst/Agents + Snowpark ML
- Ponto de entrada: Customer & Revenue Intelligence; expansão para Risk, Supply Chain, Document, Compliance
- Modelo de distribuição: Snowflake Marketplace (Native App)
- Mercado-alvo: empresas Forbes Global 2000 que já usam Snowflake

**Technical Context Observed (for Define):**

| Aspect | Observation | Implication |
|--------|-------------|-------------|
| Likely Location | `app/`, `snowflake/`, `agents/`, `pipelines/`, `models/` | Estrutura de monorepo por camada |
| Relevant KB Domains | Snowflake Native Apps, Cortex AI, Streamlit in Snowflake, Snowpark ML | Padrões documentados na Snowflake docs |
| IaC Patterns | Terraform + GitHub Actions planejados | Setup automático de ambientes dev/stage/prod |

---

## Discovery Questions & Answers

| # | Question | Answer | Impact |
|---|----------|--------|--------|
| 1 | O que você quer explorar no `/brainstorm`? | Stack e arquitetura completa | Foco em decisões técnicas fundacionais, não em features |
| 2 | Qual parte da arquitetura gera mais dúvida? | Panorama geral — chegar a uma stack mínima para o produto completo | Avaliar todas as camadas: app, dados, IA, distribuição |
| 3 | Contexto de execução e objetivo imediato? | Montar o produto completo; objetivo é gerar o arquivo SDD | Produto completo, não apenas demo — decisões precisam ser sustentáveis a longo prazo |

---

## Sample Data Inventory

| Type | Location | Count | Notes |
|------|----------|-------|-------|
| Blueprint completo | `CONTEXT.md` | 1 | 6.500+ linhas com arquitetura, módulos, schemas, roadmap, pricing |
| Estrutura de código planejada | `CONTEXT.md` seção 20 | 1 | `nexus-ai/` com app/, snowflake/, agents/, pipelines/, models/, native_app/, tests/ |
| Tabelas principais | `CONTEXT.md` seção 34 | ~17 tabelas | NEXUS_APP.CORE.*, NEXUS_APP.AI.*, NEXUS_APP.AUDIT.*, NEXUS_APP.GOVERNANCE.* |
| Modelo de dados universal | `CONTEXT.md` seção 8 | 1 | 20 entidades core: Customer, Transaction, Document, Recommendation, etc. |

**Como os samples serão usados:**
- Blueprint como fonte de verdade para os requisitos do `/define`
- Estrutura de código como ponto de partida para o `/design`
- Tabelas e entidades como base para o schema designer

---

## Approaches Explored

### Approach A: 100% Snowflake Native ⭐ Recomendado

**Description:** Produto inteiramente dentro do perímetro Snowflake. Native App Framework para distribuição, Streamlit in Snowflake para UI, Cortex AI/Search/Analyst/Agents para inteligência, Snowpark ML para modelos preditivos, Dynamic Tables + dbt para pipelines.

**Stack completo:**
```
Distribuição  → Snowflake Native App Framework + Marketplace
UI            → Streamlit in Snowflake
Agentes       → Cortex Agents (orquestra Analyst + Search)
LLMs          → Cortex AI (claude-3-5-sonnet, mistral, llama via Cortex)
Dados estruct → Cortex Analyst + Semantic Models (YAML)
Dados docs    → Cortex Search + Document AI functions
ML preditivo  → Snowpark ML (churn, forecast, anomaly)
Pipelines     → Dynamic Tables + dbt Core + Streams/Tasks
Ingestão      → Snowpipe Streaming + COPY INTO + conectores externos
Governança    → Masking Policies + Row Access Policies + Horizon Catalog
Auditoria     → Access History + Query History + tabelas AUDIT.*
IaC           → Terraform + GitHub Actions
```

**Pros:**
- Dados jamais saem do Snowflake — elimina objeção #1 de segurança enterprise (banco, saúde, telecom)
- Distribuição pelo Marketplace sem infra própria — escala sem ops
- Cortex Agents já orquestra dados estruturados (Analyst) + não estruturados (Search) nativamente
- RBAC, masking e row-level security herdados do ambiente do cliente automaticamente
- Native App = consumer instala em minutos, sem engenharia de implantação
- Modelo de precificação baseado em Snowflake credits — alinhado ao que cliente já paga

**Cons:**
- Streamlit in Snowflake tem limitações de UI (sem componentes React customizados, sem SSR)
- Cortex Agents ainda está em evolução — algumas capacidades agentic são limitadas vs LangGraph
- Custo de créditos Snowflake pode escalar com volume de perguntas LLM
- Menos controle sobre versionamento de modelos LLM (Snowflake gerencia)

**Por que Recomendado:** O diferencial central do produto é "IA segura dentro do Snowflake do cliente". Sair do Native App contradiz esse posicionamento. A limitação de UI do Streamlit é real mas gerenciável — pode ser resolvida com SPCS em v2.

---

### Approach B: Hybrid — Snowflake Data + App Externo

**Description:** Snowflake como camada de dados e IA (Cortex), mas frontend e orquestração de agentes externos: Next.js/React + Claude API ou LangGraph.

**Stack:**
```
Frontend      → Next.js + React (Vercel ou AWS)
Agentes       → Claude API (claude-sonnet-4-6) + LangGraph
Dados         → Snowflake via Snowflake Python Connector ou Snowpark
UI IA         → Vercel AI SDK + streaming
Auth          → Auth0 / Supabase Auth
```

**Pros:**
- UI sem limitações — componentes React customizados, streaming nativo, design system próprio
- Controle total sobre lógica dos agentes (state machines, tool use, memory)
- Claude API oferece capabilities mais avançadas do que Cortex Agents hoje

**Cons:**
- Dados transitam fora do Snowflake via API — objeção crítica para banco, saúde, telecom
- Infra adicional: hosting, CDN, auth, API layer, monitoramento
- Perde o canal de distribuição do Marketplace (native app listing)
- Cada cliente precisa de deploy e credenciais separadas — ops pesado
- Contradiz o posicionamento "dados no perímetro do cliente"

---

### Approach C: Native App + SPCS (Snowpark Container Services)

**Description:** Native App com containers customizados dentro do perímetro Snowflake via SPCS. Permite UI avançada (React/Vue) e lógica de agentes personalizada, sem sair do ambiente Snowflake.

**Stack:**
```
Distribuição  → Snowflake Native App Framework
UI            → React/Next.js em container SPCS
Agentes       → LangGraph ou framework customizado em container Python SPCS
Dados         → Cortex + Snowpark (mesmo que Approach A)
```

**Pros:**
- Dados ficam no perímetro Snowflake — mantém o posicionamento de segurança
- UI e lógica sem restrições do Streamlit puro
- Permite usar Claude API dentro do SPCS (dados não saem do VPC do cliente)

**Cons:**
- Complexidade operacional alta: gerenciar containers, imagens, upgrades
- SPCS tem custo adicional e curva de aprendizado significativa
- Não ideal para MVP — adiciona 2-3 meses de setup antes de qualquer feature

---

## Data Engineering Context

### Camadas de Dados Planejadas

| Camada | Schema | Conteúdo | Tecnologia |
|--------|--------|----------|------------|
| Raw Zone | `RAW.*` | Dados brutos, imutáveis | Snowpipe, COPY INTO |
| Standardized | `STD.*` | Dados limpos, padronizados | dbt staging models |
| Curated/Mart | `MART.*` | Dados prontos para negócio | dbt mart models + Dynamic Tables |
| AI Zone | `AI.*` | Features, embeddings, outputs de modelos | Snowpark ML + Cortex |
| Audit | `AUDIT.*` | Logs de acesso, prompts, ações | Streams + Tasks |
| Governance | `GOVERNANCE.*` | Resultados de qualidade de dados | Data Metric Functions |

### Data Flow

```text
[Salesforce/Zendesk/Stripe/SAP/APIs]
  ↓ Snowpipe Streaming / Fivetran / COPY INTO
[RAW Zone — dados brutos imutáveis]
  ↓ dbt staging + Dynamic Tables
[STD Zone — dados limpos e padronizados]
  ↓ dbt marts + Dynamic Tables
[MART Zone — Customer 360, Revenue, Churn Features, KPIs]
  ↓ Snowpark ML + Cortex AI
[AI Zone — embeddings, scores, recomendações, document chunks]
  ↓ Cortex Agents (Analyst + Search + Document AI)
[Streamlit UI — chat, dashboards, action center]
  ↓ Audit logs
[AUDIT Zone — rastreabilidade completa]
```

### Key Data Questions Explored

| # | Question | Answer | Impact |
|---|----------|--------|--------|
| 1 | Volume esperado de dados? | Clientes Forbes Global 2000 — TBs a PBs | Warehouse sizing XL+, Dynamic Tables com refresh incremental |
| 2 | Freshness SLA para dados de negócio? | Near real-time para alertas; daily para relatórios executivos | Snowpipe Streaming para eventos + Dynamic Tables para marts |
| 3 | Quem consome os outputs? | Executivos (chat/briefing), CS/Vendas (Customer 360), Data team (quality) | Semantic models distintos por persona; masking por role |

---

## Selected Approach

| Attribute | Value |
|-----------|-------|
| **Chosen** | Approach A — 100% Snowflake Native |
| **User Confirmation** | 2026-06-15 (implícito pelo contexto do blueprint) |
| **Reasoning** | Diferencial central é "IA segura dentro do Snowflake do cliente". Native App + Marketplace é o canal de distribuição natural. Streamlit cobre UI do MVP; SPCS é upgrade planejado para v2 quando necessário. |

---

## Key Decisions Made

| # | Decision | Rationale | Alternative Rejected |
|---|----------|-----------|----------------------|
| 1 | Distribuição via Snowflake Native App desde o início | Marketplace como canal de aquisição; dados no perímetro do cliente | App web externo (perde posicionamento de segurança) |
| 2 | Cortex Agents como runtime de agentes | Nativo no Snowflake; orquestra Analyst + Search + tools sem infra adicional | LangGraph externo (requer dados fora do Snowflake) |
| 3 | Streamlit in Snowflake para UI do MVP | Rápido de desenvolver; sem deploy adicional; suficiente para dashboard + chat | React/Next.js externo (overhead ops; SPCS reservado para v2) |
| 4 | Dynamic Tables + dbt para pipelines | Dynamic Tables para refresh automático; dbt para versionamento e testes de SQL | Spark/Databricks (fora do ecossistema; custo e ops adicionais) |
| 5 | Snowpark ML para modelos preditivos | Modelos rodam dentro do Snowflake; sem MLOps externo no MVP | SageMaker / Vertex AI (dados transitam; overhead de infra) |
| 6 | Vertical inicial: Customer & Revenue Intelligence | ROI demonstrável rápido; aplicável a SaaS, telecom, varejo, financeiro, hotelaria | Risk Intelligence (maior ticket mas ciclo de venda mais longo) |

---

## Features Removed (YAGNI)

| Feature Sugerida | Reason Removed | Can Add Later? |
|------------------|----------------|----------------|
| Fine-tuned vertical models | Cortex LLMs já suficientes para MVP; fine-tuning requer dados rotulados e ciclo longo | Sim — v3+ |
| Snowflake Marketplace de agentes (Agent marketplace) | Prematura sem produto core estabelecido | Sim — roadmap 12-24m |
| Cross-enterprise benchmarking | Requer múltiplos clientes com dados e acordos complexos de sharing | Sim — roadmap 12-24m |
| Synthetic data generation | Não necessário para MVP com dados demo | Sim — v2 |
| Multi-cloud Snowflake deployment simultâneo | Uma região por cliente é suficiente inicialmente | Sim — enterprise v2 |
| Human approval workflows complexos | Aprovar ações via UI simples é suficiente para MVP | Sim — v1 post-MVP |
| API layer pública (REST) | Consumidores primários são Streamlit e Cortex; API externa é v2 | Sim — v2 |
| Scenario simulation | Fora do escopo do MVP de Customer Intelligence | Sim — v2 |

---

## Incremental Validations

| Section | Presented | User Feedback | Adjusted? |
|---------|-----------|---------------|-----------|
| Foco do brainstorm (stack vs módulo vs GTM) | ✅ | Escolheu stack e arquitetura | Não |
| Área específica da arquitetura | ✅ | Escolheu panorama completo (stack mínima) | Não |
| Abordagens A/B/C com trade-offs | ✅ | Confirmou Approach A implicitamente; solicitou gerar SDD | Não |

---

## Suggested Requirements for /define

### Problem Statement (Draft)
Grandes empresas com Snowflake precisam transformar seus dados em decisões e ações com IA de forma segura, governada e sem mover dados para fora do ambiente, mas as ferramentas atuais (BI, chatbots genéricos, copilotos externos) não respeitam governança corporativa nem entregam ação — apenas visualização.

### Target Users (Draft)

| User | Pain Point |
|------|------------|
| CDO / Head of Data | Dados subutilizados; IA desconectada da realidade operacional |
| CFO | Precisa de forecast, impacto de margem e risco em linguagem natural, não SQL |
| Head de Customer Success | Não sabe quais contas estão em risco até ser tarde demais |
| CIO / CTO | GenAI com governança: sem vazar dados para APIs externas |
| Data Engineer | Manter pipelines, qualidade e lineage; reduzir toil manual |
| Risk & Compliance | Auditoria de quem perguntou o quê, sobre quais dados, com qual resposta |

### Success Criteria (Draft)

- [ ] Native App instalável em conta Snowflake do cliente em < 30 minutos
- [ ] Chat com dados estruturados responde em < 10 segundos com SQL rastreável
- [ ] Customer 360 consolidado a partir de ≥ 3 fontes de dados
- [ ] Churn score com explicação para top contas em risco
- [ ] Audit log completo de prompts, respostas e ações
- [ ] RBAC e masking policies respeitados automaticamente por role
- [ ] 5 vertical packs implementados (SaaS, financeiro, varejo, telecom, indústria)
- [ ] Listing funcional no Snowflake Marketplace

### Constraints Identified

- Produto deve rodar 100% dentro do perímetro Snowflake (dados não saem)
- UI limitada ao que Streamlit in Snowflake suporta no MVP (SPCS é upgrade v2)
- Custo de créditos Snowflake precisa ser monitorado e exposto ao cliente
- Native App Framework tem restrições de privilégios — o que o consumer concede ao provider
- Cortex Agents está em GA mas com limitações de tool use customizado — workarounds via Stored Procedures quando necessário

### Out of Scope (Confirmed)

- Frontend externo (React/Next.js) no MVP
- LangGraph ou LangChain para agentes (Cortex Agents é o runtime)
- Claude API direta (usar Cortex AI que já tem acesso a modelos Claude internamente)
- MLOps externo (SageMaker, Vertex, MLflow) — Snowpark ML Registry para MVP
- Suporte a plataformas que não sejam Snowflake (Databricks, BigQuery, Redshift) no v1

---

## Arquitetura de Módulos do Produto Completo

```
NEXUS AI DataOps
├── M1: AI Executive Command Center     ← Dashboard + alertas + narrativas
├── M2: Governed Enterprise AI Chat     ← RAG estruturado + não estruturado
├── M3: Document Intelligence           ← PDFs, contratos, laudos, manuais
├── M4: Predictive Operations           ← Churn, forecast, anomaly, maintenance
├── M5: Data Quality & Observability    ← Freshness, volume, schema drift
├── M6: Customer/Entity 360             ← Golden record por entidade
├── M7: AI Workflow Automation          ← Insights → ações em sistemas externos
└── M8: Governance & Compliance Center  ← RBAC, masking, audit, PII
```

**Vertical Packs (sobre os módulos core):**
```
VP1: SaaS / Customer Intelligence   ← Primeiro a implementar
VP2: Financial / Risk Intelligence
VP3: Retail Intelligence
VP4: Telecom Intelligence
VP5: Industrial Operations
VP6: Health & Field Intelligence
VP7: Hospitality Revenue Intelligence
```

---

## Estrutura de Código Planejada

```
nexus-ai/
├── app/
│   └── streamlit/
│       ├── Home.py
│       └── pages/
│           ├── 1_Executive_Command.py
│           ├── 2_Customer_360.py
│           ├── 3_AI_Chat.py
│           ├── 4_Document_Intelligence.py
│           ├── 5_Recommendations.py
│           ├── 6_Data_Quality.py
│           └── 7_Admin.py
├── snowflake/
│   ├── setup.sql
│   ├── permissions.sql
│   ├── schemas.sql
│   ├── dynamic_tables.sql
│   ├── masking_policies.sql
│   ├── row_access_policies.sql
│   ├── tasks.sql
│   ├── stored_procedures.sql
│   ├── cortex_search.sql
│   └── semantic_models/
│       ├── customer_revenue.yaml
│       └── executive_kpis.yaml
├── agents/
│   ├── executive_agent.yaml
│   ├── revenue_agent.yaml
│   ├── customer_agent.yaml
│   ├── risk_agent.yaml
│   └── data_steward_agent.yaml
├── pipelines/
│   ├── ingest_salesforce.py
│   ├── ingest_zendesk.py
│   ├── ingest_stripe.py
│   └── ingest_documents.py
├── models/
│   ├── churn_model.py
│   ├── forecast_model.py
│   ├── anomaly_model.py
│   └── recommendation_model.py
├── dbt/
│   ├── models/
│   │   ├── staging/
│   │   ├── marts/
│   │   └── ai/
│   └── dbt_project.yml
├── native_app/
│   ├── manifest.yml
│   ├── setup_script.sql
│   └── readme.md
├── terraform/
│   └── environments/
│       ├── dev/
│       ├── stage/
│       └── prod/
└── tests/
    ├── data_quality_tests.sql
    ├── agent_eval_tests.py
    └── security_tests.sql
```

---

## Session Summary

| Metric | Value |
|--------|-------|
| Questions Asked | 3 |
| Approaches Explored | 3 (A: Native, B: Hybrid, C: SPCS) |
| Features Removed (YAGNI) | 8 |
| Validations Completed | 3 |
| Approach Selected | A — 100% Snowflake Native |

---

## Next Step

**Ready for:** `/define .claude/sdd/features/BRAINSTORM_NEXUS_AI_DATAOPS.md`

> O `/define` deve capturar requisitos formais módulo a módulo, começando por **M1 (Executive Command Center)** e **M6 (Customer 360)** como core do Vertical Pack 1 (SaaS/Customer Intelligence).
