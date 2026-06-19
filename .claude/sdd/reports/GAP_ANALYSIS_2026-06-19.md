# NEXUS AI DataOps — Gap Analysis Completo
**Data:** 2026-06-19 (atualizado com auditoria de 4 agentes sobre CONTEXT.md 6532 linhas)
**Substitui:** GAP_ANALYSIS_2026-06-18.md

---

## Executive Summary

| Dimensão | Planejado (CONTEXT.md) | Implementado | Cobertura |
|---|---|---|---|
| Streamlit pages | 10 | 10 | **100%** ✅ |
| Setup SQL scripts | 27 | 27 (fora do setup_script) | **100%** ✅ (mas ⚠️ ver Gap #1) |
| Tabelas no Native App setup_script | ~38 planejadas | 22 criadas | **58%** |
| Dynamic Tables (MART) | 4 | 4 (fora do setup_script) | ⚠️ não chegam ao consumer |
| Cortex Agents | 6 planejados | 5 YAMLs | **83%** (falta Operations Agent) |
| Semantic Models | 3+ | 3 YAMLs | **100%** do MVP |
| Cortex Search services | 2 | 2 SQLs no setup_script | **100%** |
| ML Models (Python) | 4 | 2 completos + 2 stubs | **50%** |
| dbt models | ~12 | 16 | **133%** |
| Conectores de dados | 19 planejados | 3 scripts (sem trigger) | **16%** |
| Airflow DAGs | ~5 | 0 | **0%** ❌ |
| KBS (Knowledge Bases) | 8 | 0 | **0%** ❌ |
| Terraform IaC | 7 módulos | 4 módulos | **57%** |
| CI/CD workflows | 5 | 5 | **100%** ✅ |
| Acceptance tests AT-001..AT-012 | 12 | 0 | **0%** ❌ |
| Vertical Packs | 6 | 6 scripts (sem entrega) | ⚠️ fora do Native App |

**Cobertura MVP core (Native App):** ~82%
**Cobertura produto v1 completo:** ~40%

---

## O que está 100% funcional hoje

- ✅ 10 páginas Streamlit com queries reais (sem stubs)
- ✅ Schema completo: 22 tabelas + CORE.TRANSACTIONS + 5 views
- ✅ MART.CUSTOMER_360 VIEW com CTEs completos
- ✅ 5 Cortex Agents + 3 Semantic Models + 2 Cortex Search services
- ✅ RBAC (3 roles), masking policies (4 policies), row access policies, audit logging
- ✅ CI/CD: 5 workflows GitHub Actions (terraform + deploy + dbt + release)
- ✅ Demo data idempotente: 10 customers, 10 tickets, 20 events, 9 churn scores, 5 recommendations, 10 contracts, 10 subscriptions, 13 transactions — MERGE INTO no setup_script
- ✅ CORE.TRANSACTIONS criada no setup_script (era referenciada por DT_REVENUE_MOVEMENT)
- ✅ AI.CONTRACT_SEARCH (Cortex Search para contratos) no setup_script
- ✅ CORE.DOCUMENTS com colunas de contrato (contract_type, contract_value_usd, start_date, end_date, auto_renewal, governing_law, ai_summary)
- ✅ Terraform backend GCS + GCP Workload Identity implementados
- ✅ 16 dbt models (staging + intermediate + marts)
- ✅ churn_model.py + recommendation_model.py completos

---

## Gap #1 — setup_script.sql diverge dos scripts 17-27 (crítico para Native App)

Os scripts `snowflake/setup/17_dynamic_tables.sql` a `27_provider_analytics.sql` existem mas **nunca chegam ao consumer via Native App** — só rodam no CI/CD direto.

| O que falta no setup_script do Native App | Impacto |
|---|---|
| Dynamic Tables (DT_EXECUTIVE_KPIS, DT_CUSTOMER_HEALTH, DT_REVENUE_MOVEMENT, DT_FEATURE_USAGE) | Consumer não tem MART atualizado automaticamente |
| Data Metric Functions (17 DMFs de qualidade) | Consumer não tem monitoramento de qualidade |
| SP_RUN_CHURN_PIPELINE (comentado) | Churn pipeline não roda no install |
| AI.EXECUTIVE_BRIEFINGS table + task | Briefings automáticos não chegam |
| Workflow Automation (Notification Integration) | Alertas Slack/Teams não funcionam |

---

## Gap #2 — Onboarding de fontes de dados (P0)

| Item | Status | Detalhe |
|---|---|---|
| `manifest.yml` com bloco `references:` | ❌ ausente | Consumer não pode mapear suas tabelas externas na instalação |
| UI wizard de fontes (página Streamlit) | ❌ ausente | Nenhuma UI para configurar fontes de dados |
| `CORE.REGISTER_REFERENCE` SP | ✅ implementado | Mecanismo correto existe, mas sem UI e sem manifest |
| External Access Integration | ❌ comentado | `09_network_rules.sql` existe mas inativo |
| External Stages (S3, Azure Blob, GCS) | ❌ ausente | Não configurados no setup_script |

---

## Gap #3 — Orquestração e conectores (P1)

| Item | Status |
|---|---|
| Airflow / MWAA DAGs | ❌ **zero arquivos** — orquestrador principal do CONTEXT.md não existe |
| Dagster | ❌ **zero arquivos** |
| Lambda triggers para ingest_*.py | ❌ ausente |
| Snowflake Tasks no setup_script | ❌ fora do setup_script |
| Snowpipe Streaming SDK real | ⚠️ `25_snowpipe_streaming.sql` usa COPY FROM stage simulado |
| CDC com Fivetran / Debezium | ❌ ausente |
| 16 conectores de dados planejados (SAP, Oracle, HubSpot, Kafka...) | ❌ ausente |

---

## Gap #4 — Modelo de dados (tabelas ausentes)

| Tabela planejada | Status | Seção CONTEXT.md |
|---|---|---|
| `CORE.ACCOUNTS` | ❌ ausente | Seção 34 |
| `CORE.PRODUCTS` | ❌ ausente | Seção 34 |
| `CORE.INTERACTIONS` | ❌ ausente | Seção 34 |
| `AI.FEATURE_STORE` | ❌ ausente | Seção 11 |
| `AI.EMBEDDINGS` | ❌ ausente do setup_script | só em 05_ai_tables.sql |
| `AI.AGENT_MEMORY` | ❌ ausente | Seção 19 |
| `AI.MODEL_OUTPUTS` | ❌ ausente | Seção 19 |
| `KBS.DOCUMENTS`, `KBS.CHUNKS`, `KBS.SOURCES` | ❌ schema KBS inexistente | Seção 36 |

---

## Gap #5 — KBS (Knowledge Base Systems) — completamente ausente

CONTEXT.md seção 36 planeja 8 Knowledge Bases. Zero implementadas.

| Knowledge Base | Status |
|---|---|
| KB Snowflake Core | ❌ ausente |
| KB Cortex AI | ❌ ausente |
| KB MCP Protocol | ❌ ausente |
| KB Governance & Compliance | ❌ ausente |
| KB Data Engineering Patterns | ❌ ausente |
| KB Business Metrics & KPIs | ❌ ausente |
| KB Vertical Industry | ❌ ausente |
| KB Product NEXUS | ❌ ausente |

---

## Gap #6 — MCP & Multi-agente

| Item | Status | Detalhe |
|---|---|---|
| Snowflake-managed MCP Server | ⚠️ parcial | Referenciado nos YAMLs mas sem config explícita |
| `snowflake-mcp` no requirements.txt | ❌ ausente | Não instalado |
| MCP Connectors externos (Salesforce, Jira, Slack, GitHub) | ❌ ausente | Nenhum conector externo |
| Roles por agente (`AGENT_EXECUTIVE_READONLY` etc.) | ❌ ausente | Não no setup_script |
| Supervisor Agent / Roteador programático | ⚠️ parcial | `8_Agent_Workbench.py` existe sem supervisor |
| Agent 5 — Operations Agent | ❌ ausente | Só 5 de 6 agentes |

---

## Gap #7 — Segurança & Multi-tenancy

| Item | Status | Detalhe |
|---|---|---|
| Row Access Policy filtrando org_id | ❌ ausente no setup_script | org_id em todas as tabelas mas RAP não criada no Native App |
| SSO / SAML / OAuth | ❌ ausente | |
| Snowflake Secrets Manager | ❌ parcial | pipelines usam `os.getenv()` |
| Horizon Catalog / Trust Center | ❌ ausente | PII tagging existe, Trust Center não configurado |
| Model allowlist | ❌ ausente | |
| Environment separation (dev/stage/prod Terraform) | ⚠️ parcial | só `environments/prod/` |

---

## Gap #8 — Produto e páginas

| Item | Status |
|---|---|
| Página Sales Intelligence | ❌ ausente |
| Página Operations Intelligence | ❌ ausente |
| Action Center página dedicada | ⚠️ `CORE.APPROVAL_QUEUE` existe, sem página |
| Botões avançados AI Chat (salvar insight, enviar para equipe) | ❌ ausente |
| Revenue Opportunity Score | ❌ sem DT, tabela ou modelo |
| 6 Vertical Packs no setup_script + UI | ⚠️ scripts existem, fora do Native App |
| Marketplace listing files | ❌ ausente |
| Setup Wizard (installation flow) | ❌ ausente |

---

## Gap #9 — ML e AI pipelines

| Item | Status |
|---|---|
| `anomaly_model.py` | ⚠️ stub (header apenas) |
| `embedding_pipeline.py` | ⚠️ stub (header apenas) |
| SP_RUN_CHURN_PIPELINE | ⚠️ comentado no setup_script |
| Databricks para ML pesado (Fase 3) | ❌ planejado, não implementado |

---

## Gap #10 — Cloud & Infra

| Item | Status | Ver |
|---|---|---|
| External Stages S3 / Azure Blob / GCS | ❌ ausente | CLOUD_STRATEGY.md |
| Lambda triggers para ingest | ❌ ausente | CLOUD_STRATEGY.md |
| Terraform módulos security, monitoring, external | ❌ ausente | CLOUD_STRATEGY.md |
| Airflow DAGs | ❌ ausente | CLOUD_STRATEGY.md |
| Acceptance tests AT-001..AT-012 | ❌ ausente | — |

---

## Prioridade de implementação

### P0 — Bloqueadores de demo/venda real

1. `manifest.yml references:` — consumer mapeia suas tabelas no install
2. UI de onboarding de fontes de dados (wizard Streamlit)
3. Row Access Policy por org_id no setup_script do Native App
4. Ativar External Access Integration (`09_network_rules.sql`)
5. Snowflake Tasks no setup_script (substitui Airflow no curto prazo)

### P1 — SaaS robusto

6. KBS completa (8 knowledge bases + tabelas KBS.*)
7. Airflow DAGs para Salesforce/Zendesk/Stripe (3 conectores existentes)
8. External Stages S3 + Azure Blob + GCS
9. Revenue Opportunity Score (DT + modelo)
10. Roles por agente no setup_script
11. Agent 6 — Operations Agent
12. CORE.ACCOUNTS, CORE.PRODUCTS, CORE.INTERACTIONS
13. Dynamic Tables no setup_script (atualização automática para consumer)

### P2 — Produto completo

14. Página Sales Intelligence
15. Página Operations Intelligence
16. 6 Vertical Packs no setup_script + UI
17. MCP Layer configurado (Snowflake-managed + conectores externos)
18. SSO/SAML
19. Snowflake Secrets Manager (substitui os.getenv())
20. Databricks para ML pesado
21. Marketplace listing + Setup Wizard
22. Acceptance tests AT-001..AT-012

---

## Referências cruzadas

| Documento | Foco |
|---|---|
| `CLOUD_STRATEGY.md` | AWS/GCP/Azure — estratégia e implementação por cloud |
| `ARCHITECTURE.md` | Diagrama técnico do Native App |
| `DEPLOYMENT.md` | CI/CD e deploy manual |
| `CONTEXT.md` | Conceito completo (6532 linhas) |
| `.claude/sdd/features/DESIGN_NEXUS_AI_DATAOPS.md` | Design técnico detalhado |
| Memory: `audit-completo-context-2026-06-19.md` | Resumo persistido para Claude |
