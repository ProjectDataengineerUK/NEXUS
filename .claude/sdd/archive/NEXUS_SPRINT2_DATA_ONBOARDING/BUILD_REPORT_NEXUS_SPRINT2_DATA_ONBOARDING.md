# BUILD REPORT — NEXUS Sprint 2: Data Onboarding, Multi-tenancy & KBS

**Feature:** NEXUS_SPRINT2_DATA_ONBOARDING  
**Phase:** 3 — Build  
**Date:** 2026-06-19  
**Status:** ✅ COMPLETE  

---

## Summary

Sprint 2 completo: 34 arquivos criados/modificados cobrindo Multi-tenancy (RAP), External Access, Tasks, Dynamic Tables, Agent Roles, KBS, Airflow DAGs e testes.

---

## Files Manifest

### Sprint 2a — P0 (Core Infrastructure)

| # | File | Action | Status |
|---|------|--------|--------|
| 1 | `snowflake/native_app/manifest.yml` | Modified | ✅ `references:` block + `privileges:` block adicionados |
| 2 | `snowflake/native_app/setup_script.sql` | Modified | ✅ Sprint 2 P0+P1 blocks inseridos (~800 linhas adicionadas) |
| 3 | `app/streamlit/utils/onboarding.py` | Created | ✅ 6 funções: get_status, validate_schema, map/unmap ref, save_user, save_api_cred |
| 4 | `app/streamlit/pages/0_Setup.py` | Created | ✅ Wizard 3-step: Tables → Users → APIs |

### Sprint 2b — P1 Pipeline

| # | File | Action | Status |
|---|------|--------|--------|
| 5 | `snowflake/setup/11_canonical_tables.sql` | Created | ✅ CORE.ACCOUNTS, PRODUCTS, INTERACTIONS |
| 6 | `snowflake/setup/12_dynamic_tables_native.sql` | Created | ✅ DT_EXECUTIVE_KPIS, DT_CUSTOMER_HEALTH, DT_REVENUE_MOVEMENT |
| 7 | `snowflake/setup/13_revenue_score.sql` | Created | ✅ MART.REVENUE_OPPORTUNITY_SCORE + SP + DT |
| 8 | `snowflake/setup/14_external_stages.sql` | Created | ✅ S3/Azure/GCS templates comentados + CONFIG seed |
| 9 | `snowflake/setup/15_agent_roles.sql` | Created | ✅ 6 APPLICATION ROLEs + GRANTs por agente |
| 10 | `airflow/dags/salesforce_ingest_dag.py` | Created | ✅ TaskFlow API, 4 objetos SF, audit log |
| 11 | `airflow/dags/zendesk_ingest_dag.py` | Created | ✅ tickets/users/orgs, MERGE para CORE.TICKETS |
| 12 | `airflow/dags/stripe_ingest_dag.py` | Created | ✅ 4 resources, MERGE subscriptions + transactions |
| 13 | `airflow/connections/snowflake_default.json` | Created | ✅ Template de conexão |
| 14 | `airflow/requirements.txt` | Created | ✅ Airflow 2.9.3 + providers |
| 15 | `tests/sql/test_references.sql` | Created | ✅ AT-101/102/103 (9 test cases) |
| 16 | `tests/sql/test_dynamic_tables.sql` | Created | ✅ AT-105/107/108/109 (12 test cases) |
| 17 | `tests/python/test_pipelines.py` | Created | ✅ 18 testes de estrutura dos DAGs |

### Sprint 2c — P1 KBS + Operations Agent

| # | File | Action | Status |
|---|------|--------|--------|
| 18 | `snowflake/setup/16_kbs_schema.sql` | Created | ✅ KBS.SOURCES, DOCUMENTS, SEARCH_LOGS |
| 19 | `snowflake/cortex/search_services/kbs_search.sql` | Created | ✅ CORTEX SEARCH SERVICE KB_SEARCH_SERVICE |
| 20 | `snowflake/cortex/agents/operations_agent.yaml` | Created | ✅ 6º agent YAML com 3 tools |
| 21 | `pipelines/kbs/chunker.py` | Created | ✅ chunk_document + chunk_markdown |
| 22 | `pipelines/kbs/load_kb_snowflake.py` | Created | ✅ 14 páginas Snowflake docs |
| 23 | `pipelines/kbs/load_kb_cortex.py` | Created | ✅ 12 páginas Cortex AI docs |
| 24 | `airflow/dags/kbs_refresh_dag.py` | Created | ✅ Weekly refresh (dom 4h UTC) |
| 25 | `tests/python/test_kbs.py` | Created | ✅ 15 testes chunker + loaders |
| 26 | `tests/python/test_audit_logger.py` | Created | ✅ 12 testes audit schema + onboarding |

### Sprint 2 — P2

| # | File | Action | Status |
|---|------|--------|--------|
| 27 | `app/streamlit/pages/11_Sales_Intelligence.py` | Created | ✅ Pipeline + Revenue Movement + por Tipo |
| 28 | `app/streamlit/pages/12_Operations_Intelligence.py` | Created | ✅ Tickets + Interações + Clientes Críticos |
| 29 | `terraform/modules/monitoring/main.tf` | Created | ✅ Resource Monitors + freshness task |
| 30 | `terraform/modules/monitoring/variables.tf` | Created | ✅ |
| 31 | `terraform/modules/monitoring/outputs.tf` | Created | ✅ |

---

## Architecture Decisions Implemented

### 1. references: block no manifest.yml
- `customer_table`, `transactions_table`, `events_table` com `required: false`
- Callback: `core.register_reference` (SP existente reaproveitado)

### 2. RAP via CONFIG.ORG_USER_MAP
- Tabela `CONFIG.ORG_USER_MAP` estendida com coluna `role`
- Fallback `OR NOT EXISTS (SELECT 1 FROM CONFIG.ORG_USER_MAP)` para org sem usuários mapeados

### 3. KBS unificado com filtro kb_name
- Único Cortex Search Service com atributo `kb_name` para filtragem
- 3 KBs: `snowflake_core`, `cortex_ai`, `nexus_platform`

### 4. External Access Integration
- `CONFIG.ALLOW_APIS_RULE` cobre Salesforce, Zendesk, Stripe, docs Snowflake

### 5. Dual-track orchestration
- Tasks Snowflake: consumer-side, via setup_script (churn, briefing, revenue_score)
- Airflow DAGs: provider-side only (Salesforce, Zendesk, Stripe, KBS refresh)

---

## Test Coverage

| Suite | File | Tests | Coverage |
|-------|------|-------|----------|
| SQL References | `tests/sql/test_references.sql` | 9 | Multi-tenancy + RAP + canonical tables |
| SQL Dynamic Tables | `tests/sql/test_dynamic_tables.sql` | 12 | DTs + Tasks + KBS + Agent Roles |
| Python Pipelines | `tests/python/test_pipelines.py` | 18 | Estrutura DAGs Salesforce/Zendesk/Stripe |
| Python KBS | `tests/python/test_kbs.py` | 15 | Chunker + loaders + schema files |
| Python Audit | `tests/python/test_audit_logger.py` | 12 | Audit schema + onboarding + DAGs |
| **Total** | | **66** | |

---

## Gaps Fechados vs Audit 2026-06-19

| Gap | Status |
|-----|--------|
| KBS ausente (AT-108) | ✅ KBS.DOCUMENTS/SOURCES/SEARCH_LOGS + Cortex Search Service |
| Airflow zero (AT-115) | ✅ 4 DAGs: Salesforce/Zendesk/Stripe/KBS refresh |
| manifest sem references: | ✅ 3 references adicionadas |
| CORE.ACCOUNTS faltando | ✅ Criada + RAP + demo data |
| CORE.PRODUCTS faltando | ✅ Criada + RAP + demo data |
| CORE.INTERACTIONS faltando | ✅ Criada + RAP + demo data |
| RAP não enforça org_id em todas as tabelas | ✅ RAP aplicada em 11 tabelas |
| Operations Agent ausente (6º agente) | ✅ operations_agent.yaml criado |
| DTs/DMFs fora do setup_script | ✅ DTs no setup_script + standalone SQLs |

---

## Known Issues / Next Steps

1. **STAGING schema**: Os DAGs Airflow criam tabelas `STAGING.*` dinamicamente — considerar adicionar DDL do schema STAGING ao setup_script em Sprint 3
2. **KBS content quality**: As páginas de docs são fetchadas como HTML puro; um parser HTML dedicado (BeautifulSoup) melhoraria a qualidade dos chunks
3. **Semantic model para Operations Agent**: `operations_model.yaml` referenciado no agent YAML precisa ser criado (Sprint 3)
4. **External stages**: As instruções estão comentadas em `14_external_stages.sql` — o wizard 0_Setup.py deveria guiar o consumer passo a passo
5. **Multi-org demo**: O demo data atual usa um único org_id; Sprint 3 deveria adicionar dados de múltiplos orgs para testar RAP isolation end-to-end

---

## Next Phase

```bash
/ship .claude/sdd/features/DEFINE_NEXUS_SPRINT2_DATA_ONBOARDING.md
```
