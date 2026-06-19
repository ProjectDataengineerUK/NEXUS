# DEFINE: NEXUS Sprint 2 — Data Onboarding, Multi-tenancy & KBS

> Segunda fase de implementação do NEXUS AI DataOps, endereçando os gaps críticos identificados na auditoria de 2026-06-19 do CONTEXT.md (6532 linhas). Foco em: (1) permitir que consumidores reais conectem suas fontes de dados, (2) enforçar isolamento multi-tenant em runtime, (3) construir a camada de Knowledge Base Systems, (4) ativar orquestração automática.

## Metadata

| Attribute | Value |
|-----------|-------|
| **Feature** | NEXUS_SPRINT2_DATA_ONBOARDING |
| **Date** | 2026-06-19 |
| **Author** | define-agent |
| **Status** | Ready for Design |
| **Sprint anterior** | [BUILD_NEXUS_AI_DATAOPS_v1.md](../archive/BUILD_NEXUS_AI_DATAOPS_v1.md) |
| **Gap Analysis** | [GAP_ANALYSIS_2026-06-19.md](../reports/GAP_ANALYSIS_2026-06-19.md) |
| **Clarity Score** | 14/15 |

---

## Problem Statement

O NEXUS AI DataOps está ~82% funcional como Native App, mas ainda não pode ser instalado por um cliente real e gerar valor com seus próprios dados. Os três blockers são:

1. **Sem mecanismo de binding de dados do consumer**: o `manifest.yml` não declara `references:`, portanto o Snowflake Marketplace nunca pergunta ao consumer "qual é sua tabela de clientes?" durante o install. O `CORE.REGISTER_REFERENCE` SP existe mas nunca é chamado.
2. **Isolamento multi-tenant inconsistente**: `org_id` está em todas as 22 tabelas mas nenhuma Row Access Policy foi criada no `setup_script.sql` — dados de orgs diferentes ficam acessíveis entre si dentro do mesmo tenant.
3. **Ingestão sem trigger automático**: `ingest_salesforce.py`, `ingest_zendesk.py`, `ingest_stripe.py` existem mas não têm Task Snowflake nem DAG Airflow para execução automática — o dado nunca chega sem intervenção manual.

Adicionalmente, o CONTEXT.md (seções 36-38) descreve uma camada de **Knowledge Base Systems (KBS)** com 8 bases de conhecimento que fundamentam os agentes de IA — completamente ausente do código atual.

---

## Target Users

| User | Role | Pain Point neste Sprint |
|------|------|------------------------|
| CDO / Engenheiro de dados do cliente | Configuração inicial | Não consegue mapear suas tabelas Snowflake ao NEXUS no install |
| Compliance Officer | Auditoria e isolamento | Dois tenants numa mesma conta podem ver dados um do outro |
| Head of CS do cliente | Usuário final do produto | Churn scores usam dados demo, não dados reais do cliente |
| Data Engineer NEXUS | Manutenção | Precisa rodar ingestão manualmente a cada vez |
| Agentes de IA (internos) | Runtime | Agentes sem acesso a knowledge bases estruturadas produzem respostas genéricas |

---

## Goals

### P0 — Bloqueadores de demo com cliente real

| Priority | Goal |
|----------|------|
| **MUST** | Adicionar bloco `references:` ao `manifest.yml` para 3 tabelas: customers, transactions, events |
| **MUST** | Criar UI de onboarding (Streamlit wizard) que guia o consumer a mapear suas tabelas após install |
| **MUST** | Criar Row Access Policies por `org_id` diretamente no `setup_script.sql` do Native App |
| **MUST** | Ativar `EXTERNAL_ACCESS_INTEGRATION` no `09_network_rules.sql` e incluir no setup_script |
| **MUST** | Criar Snowflake Tasks no setup_script para executar os 3 pipelines de ingestão automaticamente |

### P1 — SaaS Robusto

| Priority | Goal |
|----------|------|
| **SHOULD** | Implementar KBS layer: schema KBS, tabelas, indexação e 2 knowledge bases prioritárias (Snowflake Core + Cortex AI) |
| **SHOULD** | Criar Operations Agent (6º agente) para inteligência operacional |
| **SHOULD** | Incluir Dynamic Tables (DT_EXECUTIVE_KPIS, DT_CUSTOMER_HEALTH, DT_REVENUE_MOVEMENT) no setup_script |
| **SHOULD** | Criar CORE.ACCOUNTS, CORE.PRODUCTS, CORE.INTERACTIONS (3 tabelas canônicas ausentes) |
| **SHOULD** | Implementar Revenue Opportunity Score (Dynamic Table + modelo) |
| **SHOULD** | Criar External Stages para S3, Azure Blob e GCS com Storage Integration |
| **SHOULD** | Adicionar roles por agente ao setup_script (AGENT_EXECUTIVE_READONLY etc.) |
| **SHOULD** | Criar 3 Airflow DAGs para Salesforce, Zendesk e Stripe (substituto/complemento das Tasks) |

### P2 — Produto Completo

| Priority | Goal |
|----------|------|
| **COULD** | Páginas Sales Intelligence e Operations Intelligence no Streamlit |
| **COULD** | Incluir 6 Vertical Packs no setup_script com lógica condicional por `vertical_pack` |
| **COULD** | Configurar MCP Layer (Snowflake-managed MCP + conectores externos Salesforce/Jira) |
| **COULD** | Migrar secrets de `os.getenv()` para Snowflake Secrets Manager |
| **COULD** | Implementar SSO/SAML via Snowflake Authentication Policies |
| **COULD** | Criar marketplace listing files (listing.yaml, screenshots, trial guide) |

---

## Success Criteria

- [ ] Consumer instala o Native App e vê wizard de configuração de fontes de dados como primeiro passo
- [ ] Consumer mapeia sua tabela de clientes → NEXUS popula CORE.CUSTOMERS com dados reais
- [ ] `SELECT * FROM CORE.CUSTOMERS` dentro do Native App retorna apenas linhas do org_id do tenant correto
- [ ] Ingestão de Salesforce executa automaticamente via Task Snowflake sem intervenção manual
- [ ] Agente KBS responde perguntas sobre arquitetura Snowflake com conteúdo atualizado (não alucinação)
| [ ] `manifest.yml references:` declarado e validado no Snowflake Marketplace sandbox
- [ ] Dynamic Tables no setup_script: MART.DT_EXECUTIVE_KPIS atualiza automaticamente no install do consumer
- [ ] CORE.ACCOUNTS, CORE.PRODUCTS, CORE.INTERACTIONS criadas e com demo data

---

## Acceptance Tests

| ID | Cenário | Given | When | Then |
|----|---------|-------|------|------|
| AT-101 | Consumer mapeia tabela de clientes | Consumer instala Native App via Marketplace sandbox | UI de onboarding exibe prompt "Selecione sua tabela de clientes" | CORE.REGISTER_REFERENCE chamado; CORE.CUSTOMERS populada com dados do consumer |
| AT-102 | Isolamento multi-tenant | 2 orgs (ORG-A, ORG-B) na mesma conta consumer | `SET ROLE NEXUS_ANALYST; SELECT * FROM CORE.CUSTOMERS` | Usuário ORG-A vê apenas clientes com org_id = 'ORG-A' |
| AT-103 | Task de ingestão automática | Salesforce credencial configurada em CONFIG.API_CREDENTIALS | 24h após install | CORE.CUSTOMERS atualizado com dados Salesforce sem ação manual |
| AT-104 | Agente KBS responde sobre Snowflake | KBS Snowflake Core indexada com documentação oficial | Pergunta: "Qual a diferença entre Dynamic Table e Stream?" | Resposta cita seção específica da documentação; sem alucinação |
| AT-105 | Dynamic Table no consumer | Consumer instala Nova versão do Native App | App executa setup_script.sql | `SHOW DYNAMIC TABLES` retorna DT_EXECUTIVE_KPIS com lag = 1h |
| AT-106 | External Stage S3 | Consumer configura Storage Integration para seu S3 bucket | Upload de arquivo CSV no bucket | COPY INTO CORE.TRANSACTIONS processa o arquivo automaticamente |
| AT-107 | Revenue Opportunity Score | CORE.CUSTOMERS populado com 10+ clientes | DT_REVENUE_OPPORTUNITY_SCORE atualiza | `SELECT * FROM MART.DT_REVENUE_OPPORTUNITY_SCORE` retorna score para cada cliente |
| AT-108 | Operations Agent | Pergunta sobre anomalias operacionais | Chat com Operations Agent | Resposta inclui métricas de SLA, volume de tickets e alertas |

---

## Out of Scope (Sprint 2)

- Databricks para ML pesado — Fase 3
- SSO/SAML completo — Sprint 3
- Marketplace listing público — Sprint 3
- MCP Layer completo (todos os conectores externos) — Sprint 3
- Vertical Packs 2-7 (financeiro, varejo, etc.) — Sprint 3+
- API REST pública — v2
- Snowpark Container Services (React UI) — v2

---

## Constraints

| Tipo | Constraint | Impacto |
|------|------------|---------|
| Technical | `manifest.yml references:` é GA no Snowflake Native App Framework desde 2025 | Implementação direta sem workarounds |
| Technical | Tasks no Native App requerem que o consumer conceda `EXECUTE TASK` no manifest | Grants já declarados no manifest atual |
| Technical | Row Access Policies no Native App devem usar `SYSTEM$REFERENCE()` para objetos do consumer | Padrão específico do framework |
| Technical | External Access Integration requer aprovação explícita do consumer no install | Já previsto no manifest como privilege |
| Technical | KBS usa Cortex Search — deve ser declarada no setup_script e tem custo em créditos | Indexar apenas KB prioritárias no v1 |
| Business | Dados do consumer nunca saem do Snowflake (constraint central do produto) | Todos os conectores devem usar External Stages ou APIs via External Access |
| Business | Airflow DAGs são infra do **provider** (NEXUS team) — não chegam ao consumer via Native App | DAGs ficam no repo mas rodam na infra AWS do provider |

---

## Technical Context

### Novas tecnologias que entram no Sprint 2

| Tecnologia | Uso | Documentação |
|---|---|---|
| `manifest.yml references:` | Binding de tabelas do consumer | Snowflake Native App Framework docs |
| `SYSTEM$REFERENCE()` | Acessar objetos do consumer dentro do Native App | Snowflake docs: SYSTEM$REFERENCE |
| Snowflake Secrets | Armazenar credenciais de API externas | CREATE SECRET |
| External Access Integration | Permitir chamadas HTTP a APIs externas (Salesforce, Zendesk, Stripe) | CREATE EXTERNAL ACCESS INTEGRATION |
| Snowflake Storage Integration | Conectar S3/Azure Blob/GCS como External Stage | CREATE STORAGE INTEGRATION |
| Cortex Search (KBS) | Indexar documentação técnica para RAG dos agentes | `CREATE CORTEX SEARCH SERVICE` |
| Airflow TaskFlow API 3.0 | Orquestrar DAGs de ingestão externa | docs.astronomer.io |

### Como `references:` funciona no Native App

```
Consumer instala o app
         │
         ▼
Snowflake UI mostra form: "Configurar fontes de dados"
- "Selecione sua tabela de Clientes" → consumer escolhe MY_DB.MY_SCHEMA.CUSTOMERS
- "Selecione sua tabela de Transações" → consumer escolhe BILLING.PUBLIC.INVOICES
         │
         ▼
`CORE.REGISTER_REFERENCE('customer_table', 'MY_DB.MY_SCHEMA.CUSTOMERS')` é chamado
         │
         ▼
Setup script pode usar SYSTEM$REFERENCE('CUSTOMER_TABLE') para acessar a tabela
         │
         ▼
Dynamic Table consome os dados do consumer dentro do Native App
```

### Schema KBS (novo)

```sql
-- Novo schema no setup_script
NEXUS_APP.KBS                    -- Knowledge Base Systems

NEXUS_APP.KBS.DOCUMENTS          -- Documentos fonte das KBs
NEXUS_APP.KBS.CHUNKS             -- Chunks indexados
NEXUS_APP.KBS.SOURCES            -- Referências e metadados
NEXUS_APP.KBS.SEARCH_LOGS        -- Uso e qualidade das KBs
```

---

## Data Contract (novos)

### CORE.ACCOUNTS (nova tabela)

| Column | Type | Constraints | PII? |
|--------|------|-------------|------|
| account_id | VARCHAR(36) | NOT NULL, PK | No |
| org_id | VARCHAR(50) | NOT NULL | No |
| customer_id | VARCHAR(36) | FK CORE.CUSTOMERS | No |
| account_name | VARCHAR(255) | NOT NULL | Yes — mask |
| account_type | VARCHAR(50) | | No |
| industry | VARCHAR(100) | | No |
| employee_count | INTEGER | | No |
| annual_revenue | DECIMAL(18,2) | | No |
| created_at | TIMESTAMP_TZ | NOT NULL | No |

### CORE.PRODUCTS (nova tabela)

| Column | Type | Constraints | PII? |
|--------|------|-------------|------|
| product_id | VARCHAR(36) | NOT NULL, PK | No |
| org_id | VARCHAR(50) | NOT NULL | No |
| product_name | VARCHAR(255) | NOT NULL | No |
| product_category | VARCHAR(100) | | No |
| unit_price | DECIMAL(18,2) | | No |
| is_active | BOOLEAN | DEFAULT TRUE | No |
| created_at | TIMESTAMP_TZ | NOT NULL | No |

### CORE.INTERACTIONS (nova tabela)

| Column | Type | Constraints | PII? |
|--------|------|-------------|------|
| interaction_id | VARCHAR(36) | NOT NULL, PK | No |
| org_id | VARCHAR(50) | NOT NULL | No |
| customer_id | VARCHAR(36) | FK CORE.CUSTOMERS | No |
| channel | VARCHAR(50) | email/call/chat/meeting | No |
| direction | VARCHAR(10) | inbound/outbound | No |
| subject | VARCHAR(500) | | No |
| sentiment_score | DECIMAL(4,2) | -1.0 to 1.0 | No |
| occurred_at | TIMESTAMP_TZ | NOT NULL | No |

### KBS.DOCUMENTS (nova tabela)

| Column | Type | Constraints | PII? |
|--------|------|-------------|------|
| doc_id | VARCHAR(36) | NOT NULL, PK | No |
| kb_name | VARCHAR(100) | NOT NULL | No |
| title | VARCHAR(500) | NOT NULL | No |
| content | TEXT | NOT NULL | No |
| source_url | VARCHAR(1000) | | No |
| doc_type | VARCHAR(50) | official_doc/tutorial/best_practice | No |
| version | VARCHAR(20) | | No |
| indexed_at | TIMESTAMP_TZ | | No |
| is_active | BOOLEAN | DEFAULT TRUE | No |

---

## Módulos e Verticais Novos

### Módulo 0 — Data Onboarding Wizard (novo)

| Feature | Priority | Descrição |
|---------|----------|-----------|
| Wizard de configuração de fontes | MUST | Página Streamlit que guia o mapeamento de tabelas do consumer |
| Validação de schema das tabelas mapeadas | MUST | Verificar se a tabela tem as colunas mínimas esperadas |
| Status de onboarding por fonte | SHOULD | Mostrar quais fontes estão conectadas, última sincronização |
| Botão "Usar dados demo" | MUST | Manter fallback para demo data quando consumer não mapeia fontes |

### Módulo KBS (novo)

| Knowledge Base | Conteúdo | Fonte | Prioridade |
|---|---|---|---|
| KB Snowflake Core | Documentação oficial Snowflake (Native App, Dynamic Tables, Tasks, Cortex) | docs.snowflake.com | P1 |
| KB Cortex AI | Guias de Cortex Agents, Analyst, Search, Document AI | docs.snowflake.com/cortex | P1 |
| KB Governance | RBAC, masking policies, row access, compliance | docs.snowflake.com/security | P2 |
| KB Data Engineering | Patterns de ingestão, Snowpipe, External Stages, Airflow | docs.astronomer.io + Snowflake | P2 |
| KB Business Metrics | Definições de ARR, MRR, Churn, NPS, LTV, CAC | Internal NEXUS docs | P2 |
| KB Vertical Industry SaaS | Benchmarks SaaS: churn, NPS, ARR growth | Curated sources | P3 |
| KB MCP Protocol | Snowflake-managed MCP, conectores externos | docs.snowflake.com/mcp | P3 |
| KB Product NEXUS | Documentação interna do produto NEXUS | Internal | P3 |

---

## Roadmap de Releases

| Release | Conteúdo | Gate de Sucesso |
|---------|----------|-----------------|
| **Sprint 2a (P0 — 2 semanas)** | `manifest.yml references:` + UI wizard + RAP no setup_script + External Access ativo | AT-101, AT-102 passing |
| **Sprint 2b (P1 — 4 semanas)** | Tasks de ingestão + Dynamic Tables no setup_script + 3 tabelas canônicas + Revenue Score | AT-103, AT-105, AT-107 passing |
| **Sprint 2c (P1 — 4 semanas)** | KBS layer (2 KBs prioritárias) + Operations Agent + External Stages | AT-104, AT-108 passing |
| **Sprint 3 (P2 — 6 semanas)** | Páginas Sales/Ops Intelligence + Vertical Packs setup_script + MCP Layer | 3 pilotos com dados reais |

---

## Open Questions

1. **Qual cloud é primária para o provider?** AWS-first (Lambda + MWAA) ou GCP-first (Cloud Run + Cloud Composer)? O `bootstrap.sh` atual usa GCS para Terraform state — seguir GCP ou migrar para AWS?
2. **KBS: quais as 2 KBs prioritárias para Sprint 2c?** Snowflake Core + Cortex AI são propostas; confirmar com time se há outra mais urgente.
3. **Operations Agent: quais ferramentas (tools)?** Sugestão: DMF results + AUDIT.ACTION_LOG + CORE.TICKETS + MART.DT_CUSTOMER_HEALTH. Confirmar escopo.
4. **External Stages: S3 first ou Azure Blob first?** Depende do primeiro cliente real — se for empresa Microsoft, Azure Blob. Se for startup, S3.
5. **Airflow vs Snowflake Tasks como orquestrador primário?** Tasks são mais simples de manter (dentro do Snowflake), mas Airflow tem retry + monitoring + DAG UI. Recomendação: Tasks para MVP, Airflow para clientes enterprise.

---

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-06-19 | define-agent | Versão inicial — baseado em gap analysis de 4 agentes sobre CONTEXT.md 6532 linhas |

---

## Next Step

**Ready for:** `/design .claude/sdd/features/DEFINE_NEXUS_SPRINT2_DATA_ONBOARDING.md`

> O `/design` deve iniciar pelo **bloco P0** (manifest.yml + RAP no setup_script + External Access) pois são pré-requisitos para qualquer demo com cliente real. Depois **P1** (Tasks + Dynamic Tables + 3 tabelas + KBS mínima). O Operations Agent e External Stages podem ser paralelos à KBS.
>
> Ordem de build recomendada:
> 1. `manifest.yml` com `references:` + `CORE.REGISTER_REFERENCE` SP atualizado
> 2. Row Access Policies no `setup_script.sql` (usando `CURRENT_USER()` → `org_id`)
> 3. External Access Integration ativo no `09_network_rules.sql`
> 4. UI wizard de onboarding (nova página Streamlit `0_Setup.py`)
> 5. Snowflake Tasks no setup_script para os 3 pipelines de ingestão
> 6. Dynamic Tables no setup_script (DT_EXECUTIVE_KPIS, DT_CUSTOMER_HEALTH, DT_REVENUE_MOVEMENT)
> 7. CORE.ACCOUNTS + CORE.PRODUCTS + CORE.INTERACTIONS + demo data
> 8. KBS schema + tabelas + indexação de 2 KBs prioritárias
> 9. Operations Agent YAML
> 10. External Stages (S3 + Azure Blob + GCS) + Storage Integrations
> 11. Revenue Opportunity Score DT + modelo
> 12. Roles por agente no setup_script
