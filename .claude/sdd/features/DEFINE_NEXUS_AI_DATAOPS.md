# DEFINE: NEXUS AI DataOps — Enterprise AI Command Center em Snowflake

> Plataforma nativa em Snowflake que transforma dados de grandes empresas em decisões, ações e receita através de agentes de IA governados, distribuída como Snowflake Native App via Marketplace.

## Metadata

| Attribute | Value |
|-----------|-------|
| **Feature** | NEXUS_AI_DATAOPS |
| **Date** | 2026-06-15 |
| **Author** | define-agent |
| **Status** | Ready for Design |
| **Clarity Score** | 14/15 |
| **Source** | BRAINSTORM_NEXUS_AI_DATAOPS.md |

---

## Problem Statement

Grandes empresas que já investiram em Snowflake têm seus dados subutilizados porque as ferramentas disponíveis (BI, chatbots genéricos, copilotos externos) não respeitam a governança corporativa, movem dados para fora do ambiente seguro e entregam apenas visualização — não decisão nem ação. O custo dessa lacuna é mensurado em receita em risco não detectada, churn de clientes não antecipado, contratos com riscos não identificados e decisões executivas tomadas com dados defasados ou incompletos.

---

## Target Users

| User | Role | Pain Point |
|------|------|------------|
| CDO / Head of Data | Estratégia de dados | IA desconectada da realidade operacional; pilotos que não chegam à produção |
| CFO | Finanças executivas | Precisa de forecast, impacto de margem e risco em linguagem natural, não SQL |
| Head de Customer Success | Retenção e saúde de clientes | Descobre clientes em risco apenas quando o churn já ocorreu |
| CIO / CTO | Infraestrutura e governança | GenAI sem vazamento de dados: modelos que respeitem RBAC, masking e compliance |
| Data Engineer | Pipelines e qualidade | Manter pipelines, qualidade e lineage com visibilidade de impacto no negócio |
| Risk & Compliance Officer | Auditoria e regulação | Rastrear quem perguntou o quê, sobre quais dados, com qual resposta de IA |
| CMO / Head de Marketing | Campanhas e segmentação | Segmentação de clientes governada, sem exportar dados para ferramentas externas |
| COO / Head de Operações | Eficiência operacional | Detectar gargalos e anomalias antes que impactem clientes ou receita |

---

## Goals

| Priority | Goal |
|----------|------|
| **MUST** | Distribuir o produto como Snowflake Native App instalável em < 30 min sem engenharia do cliente |
| **MUST** | Entregar Customer 360 consolidado a partir de ≥ 3 fontes de dados (CRM, billing, suporte) |
| **MUST** | Chat com dados estruturados via Cortex Analyst com SQL rastreável e citação de fonte |
| **MUST** | Chat com documentos via Cortex Search (contratos, tickets, políticas) com RAG governado |
| **MUST** | Churn score com explicação de drivers e recomendação de ação para top contas em risco |
| **MUST** | RBAC e masking policies do Snowflake do cliente respeitados automaticamente por agente |
| **MUST** | Audit log completo: quem perguntou, quando, sobre quais dados, com qual resposta |
| **SHOULD** | Dashboard executivo com KPIs, alertas de anomalia e narrativas automáticas (AI Briefing) |
| **SHOULD** | Action Center com fila de recomendações priorizadas por impacto financeiro estimado |
| **SHOULD** | Document Intelligence: extração de campos, resumo e identificação de riscos em PDFs |
| **SHOULD** | Data Quality & Observability: freshness, volume anomaly, schema drift por domínio |
| **SHOULD** | Vertical Pack 1 completo: SaaS / Customer & Revenue Intelligence |
| **COULD** | Workflow Automation: transformar recomendações em tarefas no CRM/Jira/ServiceNow |
| **COULD** | Vertical Packs 2-7 (financeiro, varejo, telecom, indústria, saúde, hotelaria) |
| **COULD** | Listing publicado no Snowflake Marketplace com demo dataset |

---

## Success Criteria

- [ ] Native App instalável em conta Snowflake do cliente em < 30 minutos via `setup_script.sql`
- [ ] Chat com dados estruturados retorna resposta em < 10 segundos com SQL rastreável e gráfico automático
- [ ] Customer 360 consolida dados de ≥ 3 fontes sem engenharia adicional do cliente
- [ ] Churn score calculado para 100% da base de clientes com `top_drivers` e `recommended_action`
- [ ] RBAC nativo: usuário sem permissão não vê dados mascarados mesmo via chat de linguagem natural
- [ ] Audit log registra 100% das interações com agente (prompt, fonte, resposta, user, timestamp)
- [ ] Data Quality score visível por domínio com alerta automático em caso de freshness > SLA
- [ ] Vertical Pack 1 cobre: Customer 360, Churn Score, Revenue Forecast, Contract Intelligence, Executive Briefing
- [ ] Zero dados trafegam para fora do perímetro Snowflake do cliente em qualquer fluxo
- [ ] Custo de créditos Snowflake por pergunta monitorado e visível no Admin Console

---

## Acceptance Tests

| ID | Scenario | Given | When | Then |
|----|----------|-------|------|------|
| AT-001 | Instalação do Native App | Conta Snowflake com ACCOUNTADMIN | Executa `setup_script.sql` e concede privilégios | App aparece no Streamlit Apps, schemas `NEXUS_APP.*` criados |
| AT-002 | Chat com dados estruturados | Usuário autenticado com role `ANALYST` | Pergunta "Quais contas têm maior risco de churn?" | Resposta com lista rankeada, SQL gerado visível, resposta em < 10s |
| AT-003 | RBAC automático | Usuário com role sem acesso a `PII_DATA` | Pergunta "Qual o email do cliente X?" | Campo mascarado (`****@****.com`) na resposta; sem erro de permissão |
| AT-004 | Chat com documentos | 10 contratos PDF ingeridos no Cortex Search | Pergunta "Quais contratos vencem nos próximos 60 dias?" | Resposta com lista de contratos, citação de parágrafo fonte |
| AT-005 | Customer 360 | Dados de Salesforce, Zendesk e Stripe no schema RAW | Clica em cliente na lista de risco | Tela exibe: ARR, tickets abertos, uso do produto, score de churn, próxima ação |
| AT-006 | Churn score | `MART.CHURN_FEATURES` populado via Dynamic Table | Dynamic Table faz refresh | `AI.CHURN_SCORES` atualizado com `churn_probability`, `risk_level`, `top_drivers`, `recommended_action` |
| AT-007 | Audit log | Admin abre Governance Center | Clica em "Audit Log" | Vê tabela com `user`, `prompt`, `data_sources_accessed`, `response_summary`, `timestamp` para cada interação |
| AT-008 | Data quality alert | Tabela `STD.CUSTOMERS` não atualiza por > 24h | Sistema executa Data Metric Function de freshness | Alerta exibido no dashboard com impacto: "Churn score desatualizado; 3 alertas pendentes afetados" |
| AT-009 | Zero data exfiltration | Cortex Agent ativo com pergunta sobre dados PII | Agente usa `CORTEX_SEARCH` e `CORTEX_ANALYST` | Nenhuma chamada de API para fora do Snowflake nos logs de `NETWORK_RULE` |
| AT-010 | Executive AI Briefing | Segunda-feira, 08:00 UTC | Task Snowflake executa geração de briefing | Email/Slack recebe PDF com: mudanças semana anterior, top 3 riscos, top 3 oportunidades, ações sugeridas |
| AT-011 | Mascaramento de PII em resposta de agente | Política de masking ativa em `CUSTOMER.EMAIL` | Agente responde sobre cliente específico | Email aparece como `j***@example.com` na resposta, independente do modelo LLM usado |
| AT-012 | Custo por pergunta | Admin acessa "Cost Monitor" no Admin Console | 1.000 perguntas processadas | Exibe custo total em créditos Snowflake por dia, por agente, por usuário |

---

## Out of Scope

- Frontend externo (React/Next.js) hospedado fora do Snowflake — reservado para SPCS v2
- LangChain, LangGraph ou qualquer framework de agentes externo — Cortex Agents é o runtime
- Claude API direta — usar Cortex AI que já inclui modelos Claude internamente
- MLOps externo: SageMaker, Vertex AI, MLflow — Snowpark ML Registry para modelos preditivos
- Suporte a plataformas que não sejam Snowflake (Databricks, BigQuery, Redshift) no v1
- Fine-tuning de modelos por vertical — Cortex LLMs base são suficientes para v1
- API REST pública para consumidores externos — v2
- Agent Marketplace (distribuição de agentes de terceiros) — roadmap 12-24m
- Cross-enterprise benchmarking entre clientes — requer data sharing agreements complexos
- Scenario simulation / what-if analysis — v2
- Human approval workflows complexos (multi-step, multi-approver) — v1 post-MVP
- Synthetic data generation — não necessário com demo dataset

---

## Constraints

| Type | Constraint | Impact |
|------|------------|--------|
| Technical | 100% dentro do perímetro Snowflake — sem chamadas API externas em produção | Todo o processamento LLM usa Cortex AI; sem HTTP para fora do Snowflake |
| Technical | UI limitada ao Streamlit in Snowflake no MVP | Sem componentes React customizados; SPCS é upgrade planejado para v2 |
| Technical | Native App Framework: consumer controla quais privilégios concede ao provider | Setup script deve solicitar apenas os grants mínimos necessários |
| Technical | Cortex Agents em GA mas com limitações em tool use customizado | Workarounds via Stored Procedures Python quando necessário |
| Technical | Cortex AI cobra em Snowflake credits (tokens) — custo variável por pergunta | Cache de respostas frequentes; warehouse sizing cuidadoso; monitoring de custo obrigatório |
| Technical | Streamlit in Snowflake: limite de memória e CPU por sessão | Queries pesadas devem rodar em warehouse separado, não no processo Streamlit |
| Business | Dados do cliente nunca saem do Snowflake — é o diferencial central | Restringe o uso de APIs externas de IA; reforça RBAC nativo |
| Business | Distribuição via Snowflake Marketplace (Native App) desde o início | Arquitetura provider/consumer do Native App Framework deve ser respeitada |

---

## Technical Context

| Aspect | Value | Notes |
|--------|-------|-------|
| **Deployment Location** | `native_app/`, `app/streamlit/`, `snowflake/`, `agents/`, `models/`, `dbt/` | Monorepo por camada funcional |
| **KB Domains** | Snowflake Native Apps, Cortex AI/Search/Analyst/Agents, Streamlit in Snowflake, Snowpark ML, dbt Core | Padrões em docs.snowflake.com e quickstarts oficiais |
| **IaC Impact** | Novos recursos: warehouses, schemas, databases, network rules, masking policies, tasks | Terraform para provisionamento de ambientes dev/stage/prod |

**Stack Completo Confirmado (Approach A — 100% Snowflake Native):**

```
Distribuição   → Snowflake Native App Framework + Marketplace
UI             → Streamlit in Snowflake
Agentes        → Cortex Agents (orquestra Analyst + Search + tools)
LLMs           → Cortex AI (Claude 3.5 Sonnet, Mistral, Llama via Cortex)
Dados estruct  → Cortex Analyst + Semantic Models (YAML)
Dados docs     → Cortex Search + Document AI functions
ML preditivo   → Snowpark ML (churn, forecast, anomaly)
Pipelines      → Dynamic Tables + dbt Core + Streams/Tasks
Ingestão       → Snowpipe Streaming + COPY INTO + conectores (Fivetran/Airbyte)
Governança     → Masking Policies + Row Access Policies + Horizon Catalog
Auditoria      → Access History + Query History + AUDIT.* tables
IaC            → Terraform + GitHub Actions
```

---

## Data Contract

### Source Inventory (Vertical Pack 1 — Customer Intelligence)

| Source | Type | Volume Estimado | Freshness SLA | Owner |
|--------|------|-----------------|---------------|-------|
| Salesforce (CRM) | API / Fivetran | ~10k-500k registros/conta | Daily refresh | Customer team |
| Zendesk (suporte) | API / Fivetran | ~1k-100k tickets/mês | Near real-time (Snowpipe) | Support team |
| Stripe / Billing | API / Fivetran | ~5k-1M transações/mês | Daily refresh | Finance team |
| Product Events | Kafka → Snowpipe Streaming | ~1M-1B eventos/mês | Real-time (< 1 min) | Product team |
| Contratos PDF | S3 / Stage | ~10-10k documentos | Event-driven (novo upload) | Legal team |
| NPS / Survey | API | ~1k-50k respostas/trimestre | Weekly | CX team |

### Schema Core Contract

**NEXUS_APP.CORE.CUSTOMERS**

| Column | Type | Constraints | PII? |
|--------|------|-------------|------|
| customer_id | VARCHAR(36) | NOT NULL, PK | No |
| name | VARCHAR(255) | NOT NULL | Yes — mask para non-admin |
| email | VARCHAR(255) | UNIQUE | Yes — mask |
| segment | VARCHAR(50) | NOT NULL | No |
| region | VARCHAR(50) | NOT NULL | No |
| industry | VARCHAR(100) | | No |
| lifecycle_stage | VARCHAR(50) | | No |
| arr | DECIMAL(18,2) | | No |
| created_at | TIMESTAMP_TZ | NOT NULL | No |
| updated_at | TIMESTAMP_TZ | NOT NULL | No |

**NEXUS_APP.AI.CHURN_SCORES**

| Column | Type | Constraints | PII? |
|--------|------|-------------|------|
| score_id | VARCHAR(36) | NOT NULL, PK | No |
| customer_id | VARCHAR(36) | NOT NULL, FK | No |
| churn_probability | DECIMAL(5,4) | 0.0000-1.0000 | No |
| risk_level | VARCHAR(10) | HIGH/MEDIUM/LOW | No |
| top_drivers | VARIANT | JSON array | No |
| recommended_action | VARCHAR(500) | | No |
| expected_revenue_at_risk | DECIMAL(18,2) | | No |
| model_version | VARCHAR(20) | | No |
| scored_at | TIMESTAMP_TZ | NOT NULL | No |

**NEXUS_APP.AUDIT.PROMPT_LOG**

| Column | Type | Constraints | PII? |
|--------|------|-------------|------|
| log_id | VARCHAR(36) | NOT NULL, PK | No |
| session_id | VARCHAR(36) | NOT NULL | No |
| user_name | VARCHAR(255) | NOT NULL | Yes — mask |
| role_name | VARCHAR(255) | NOT NULL | No |
| agent_id | VARCHAR(50) | | No |
| prompt_text | TEXT | NOT NULL | Yes — redact PII before storing |
| data_sources | VARIANT | JSON array de tabelas acessadas | No |
| response_summary | TEXT | | No |
| cortex_tokens_used | INTEGER | | No |
| latency_ms | INTEGER | | No |
| created_at | TIMESTAMP_TZ | NOT NULL | No |

### Freshness SLAs

| Layer | Target | Medição |
|-------|--------|---------|
| RAW.* | < 15 min para eventos streaming; < 6h para batch | `MAX(loaded_at)` vs `NOW()` |
| STD.* | < 1h após RAW disponível | Dynamic Table `lag` configuration |
| MART.* | Atualizado até 06:00 UTC daily para relatórios executivos | Task de monitoramento + Data Metric Function |
| AI.CHURN_SCORES | Refresh diário após MART.CHURN_FEATURES | Dynamic Table trigger |
| AI.EMBEDDINGS | Incremental: novos documentos em < 30 min | Stream + Task sobre CORE.DOCUMENTS |

### Completeness Metrics

- 99.9% dos registros de fonte presentes no STD layer dentro do SLA
- Zero null em colunas PK (`customer_id`, `score_id`, `log_id`)
- 100% dos churn scores gerados para clientes com `lifecycle_stage = 'active'`
- 100% das interações com Cortex Agents registradas no AUDIT.PROMPT_LOG

### Lineage Requirements

- Lineage coluna a coluna de RAW → STD → MART para tabelas core (via dbt exposures)
- Impact analysis automático: mudança de schema em RAW deve alertar sobre marts dependentes
- Horizon Catalog como fonte de verdade para data products internos

---

## Módulos e Vertical Packs

### Módulos Core (M1-M8)

| ID | Módulo | Priority | Descrição |
|----|--------|----------|-----------|
| M1 | AI Executive Command Center | MUST | Dashboard + alertas + KPIs + narrativas automáticas |
| M2 | Governed Enterprise AI Chat | MUST | RAG sobre dados estruturados + documentos com permissão por role |
| M3 | Document Intelligence | SHOULD | Extração, resumo e análise de risco em PDFs |
| M4 | Predictive Operations | MUST | Churn, forecast, anomaly detection, manutenção preditiva |
| M5 | Data Quality & Observability | SHOULD | Freshness, volume, schema drift, score de confiabilidade |
| M6 | Customer / Entity 360 | MUST | Golden record consolidado por entidade (cliente, conta, produto) |
| M7 | AI Workflow Automation | COULD | Insights → ações em CRM/Jira/ServiceNow via External Access |
| M8 | Governance & Compliance Center | MUST | RBAC, masking, audit log, PII discovery, prompt logging |

### Vertical Packs (VP1-VP7)

| ID | Pack | Priority | Módulos Core Usados | Primeiro Lançamento |
|----|------|----------|--------------------|--------------------|
| VP1 | SaaS / Customer & Revenue Intelligence | MUST | M1, M2, M3, M4, M6, M8 | MVP |
| VP2 | Financial / Risk Intelligence | SHOULD | M1, M2, M3, M4, M8 | v1.1 |
| VP3 | Retail Intelligence | SHOULD | M1, M2, M4, M5, M6 | v1.2 |
| VP4 | Telecom Intelligence | SHOULD | M1, M2, M4, M5, M6, M8 | v1.2 |
| VP5 | Industrial Operations | COULD | M1, M2, M3, M4, M5 | v2 |
| VP6 | Health & Field Intelligence | COULD | M1, M2, M3, M4, M8 | v2 |
| VP7 | Hospitality Revenue Intelligence | COULD | M1, M2, M4, M5, M6 | v2 |

### Agentes por Vertical Pack 1 (SaaS/Customer)

| Agente | Audience | Tools | Output Principal |
|--------|----------|-------|-----------------|
| Executive Analyst | CEO, CFO, COO | Cortex Analyst + Search + briefing generator | KPIs + causas + ações da semana |
| Revenue Agent | CRO, Vendas | Cortex Analyst (revenue marts) | Pipeline health, forecast, upsell |
| Customer Intelligence Agent | CS, CX | Cortex Analyst + Search (tickets + contratos) | Customer 360, churn risk, next action |
| Risk & Compliance Agent | Legal, Compliance | Cortex Search (docs) + Audit tables | Análise de contratos, PII audit |
| Data Steward Agent | Data Engineers | Data Metric Functions + lineage | Quality alerts, schema drift, cost |

---

## Estrutura de Schemas Snowflake

```sql
-- Databases
NEXUS_APP          -- App principal (consumer)
NEXUS_PROVIDER     -- Package e setup (provider)

-- Schemas em NEXUS_APP
NEXUS_APP.CORE          -- Entidades consolidadas (Customer, Product, Transaction...)
NEXUS_APP.RAW           -- Dados brutos de fontes (espelhos das fontes externas)
NEXUS_APP.STD           -- Dados padronizados (dbt staging)
NEXUS_APP.MART          -- Marts de negócio (Customer 360, Revenue, Churn Features)
NEXUS_APP.AI            -- Outputs de IA (scores, embeddings, recomendações, sessões)
NEXUS_APP.AUDIT         -- Logs de acesso, prompts, ações, data quality
NEXUS_APP.GOVERNANCE    -- Resultados de Data Metric Functions, policies
NEXUS_APP.CONFIG        -- Configurações do app (vertical pack, roles, thresholds)
```

---

## Assumptions

| ID | Assumption | If Wrong, Impact | Validated? |
|----|------------|------------------|------------|
| A-001 | Cliente já tem conta Snowflake Enterprise ou Business Critical | Native App não é possível em Standard; modelo de negócio muda | [ ] |
| A-002 | Cortex AI (incluindo Claude via Cortex) disponível na região do cliente | Modelos LLM indisponíveis — fallback para modelos open-source via Cortex | [ ] |
| A-003 | Cliente pode conceder ao Native App os privilégios necessários (CREATE TABLE, USAGE em warehouses) | Setup falha — precisaria de simplificação de permissões | [ ] |
| A-004 | Latência do Cortex Analyst < 10s para queries em marts com < 100M linhas | Precisaria de caching agressivo e warehouse XL para manter SLA | [ ] |
| A-005 | Streamlit in Snowflake suporta as visualizações necessárias (charts, tables, chat UI) | Limitação de UI requereria SPCS antecipadamente | [ ] |
| A-006 | dbt Core (open source) é suficiente para transformações no MVP | dbt Cloud teria funcionalidades adicionais mas não são necessárias para v1 | [ ] |
| A-007 | Fivetran ou Airbyte do cliente já existem ou cliente aceita configurar conectores | Precisaria de conectores nativos adicionais ou ingestion manual via COPY INTO | [ ] |
| A-008 | Snowflake Marketplace permite listing de Native Apps com trial/demo | Canal de distribuição principal; se mudar, impacta GTM significativamente | [ ] |

---

## Roadmap de Releases

| Release | Conteúdo Principal | Success Gate |
|---------|-------------------|--------------|
| **MVP (0-90 dias)** | M1+M2+M4+M6+M8 completos; VP1 (SaaS); 3 conectores; Native App instalável; demo dataset | 2 pilotos pagantes ativos |
| **v1.0 (90-180 dias)** | M3+M5+M7; 5+ conectores; Marketplace listing; Admin Console; VP1 completo | Listing no Marketplace; NPS > 40 |
| **v1.1 (180-270 dias)** | VP2 (Financeiro) + VP3 (Varejo); Model evaluation; Agent evaluation framework | 5 clientes enterprise ativos |
| **v1.2 (270-365 dias)** | VP4 (Telecom) + VP5 (Indústria); SPCS para UI avançada (opcional) | ARR > US$ 1M |
| **v2.0 (365+ dias)** | VP6+VP7; Agent marketplace; Cross-enterprise insights; API REST pública | Scale via parceiros |

---

## Clarity Score Breakdown

| Element | Score (0-3) | Notes |
|---------|-------------|-------|
| Problem | 3 | Específico: quem tem o problema, qual o impacto, por que as soluções atuais falham |
| Users | 3 | 8 personas com role e pain point definidos; buyers e users distintos |
| Goals | 2 | MoSCoW definido; goals MUST bem especificados; alguns SHOULD/COULD ainda amplos |
| Success | 3 | 10 critérios mensuráveis com números, SLAs e condições testáveis |
| Scope | 3 | 12 itens explicitamente fora de escopo; out of scope inclui razão e versão futura |
| **Total** | **14/15** | Acima do mínimo de 12 — pronto para Design |

---

## Open Questions

1. **Região Snowflake do cliente**: o produto deve suportar múltiplas regiões AWS/Azure/GCP desde o Native App, ou iniciar com uma região e expandir? Impacta setup do Cortex AI (disponibilidade por região).
2. **Modelo LLM padrão no Cortex**: qual modelo usar por padrão para o chat — `claude-3-5-sonnet` via Cortex ou `mistral-large2`? Impacta custo/pergunta e qualidade das respostas.
3. **Pricing final**: o produto é cobrado em $ flat/mês ou em Snowflake credits consumidos? Impacta a experiência no Marketplace e a conversa de venda.

---

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-06-15 | define-agent | Versão inicial a partir de BRAINSTORM_NEXUS_AI_DATAOPS.md |

---

## Next Step

**Ready for:** `/design .claude/sdd/features/DEFINE_NEXUS_AI_DATAOPS.md`

> O `/design` deve cobrir a arquitetura técnica completa, começando pelo **Native App setup** e **M1+M2+M6+M8** como core do MVP (VP1 — SaaS/Customer Intelligence).
