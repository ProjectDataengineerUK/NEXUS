# DEFINE — NEXUS Sprint 4: Conectores Adicionais + CDC via Streams

**Feature:** NEXUS_SPRINT4_CONNECTORS_CDC
**Phase:** 1 — Define
**Date:** 2026-07-06
**Status:** Draft

---

## Problem Statement

Sprint 2 entregou 3 conectores Airflow (Salesforce, Zendesk, Stripe), todos fazendo **full extraction** a cada run — cada DAG relê o dataset inteiro da API de origem e faz MERGE completo no Snowflake. Isso tem três problemas:

1. **Sem cobertura de ERPs enterprise** — clientes com SAP ou Oracle (comum no ICP financeiro/indústria do NEXUS) não têm conector; hoje só CRM (Salesforce), Suporte (Zendesk) e Billing (Stripe) são cobertos.
2. **Sem CDC incremental** — todo refresh relê o dataset completo da fonte, mesmo quando só uma fração das linhas mudou. Isso escala mal (mais linhas = mais tempo/custo de API + warehouse) e não é como pipelines de produção deveriam funcionar.
3. **Nenhum Stream sobre tabelas de negócio** — os únicos Streams existentes (`CONFIG.DOCUMENTS_PENDING_STREAM`, `CONFIG.AGENT_MESSAGES_STREAM`) servem para triggers de processamento Cortex, não para propagar mudanças incrementais de `CORE.TRANSACTIONS`/`CORE.CUSTOMERS` para os marts (`MART.DT_*`).

---

## Users

| Persona | Dor | Prioridade |
|---------|-----|-----------|
| **Cliente enterprise (financeiro/indústria)** | Dados vivem em SAP/Oracle, não em Salesforce/Stripe — sem conector, não consegue popular o NEXUS | P0 |
| **Cliente HubSpot (SMB/mid-market)** | CRM mais comum nesse segmento não é coberto | P1 |
| **Provider (custo de operação)** | Full extraction diário desperdiça API quota e créditos Snowflake conforme volume de dados cresce | P0 |
| **Provider (latência)** | Dynamic Tables com `TARGET_LAG = '1 hour'` recalculam do zero mesmo sem mudança nos dados de origem | P1 |

---

## Goals

1. **Conector SAP** — extração via SAP OData/RFC (escopo: tabelas de clientes, faturas, pedidos) para `STAGING.SAP_*`
2. **Conector Oracle** — extração via Oracle DB connection (JDBC/oracledb) para `STAGING.ORACLE_*`
3. **Conector HubSpot** — extração via HubSpot API (contacts, deals, companies) para `STAGING.HUBSPOT_*`, seguindo o padrão dos 3 conectores existentes
4. **CDC via Streams** — `CREATE STREAM` sobre `CORE.TRANSACTIONS`, `CORE.CUSTOMERS`, `CORE.SUBSCRIPTIONS` no lado do consumer (setup_script.sql), consumidos por Tasks que fazem MERGE incremental nos marts em vez de full recompute
5. **Padronizar staging multi-fonte** — todos os novos conectores escrevem em `STAGING.<FONTE>_<OBJETO>` (schema `STAGING` já criado no Sprint 3) antes do MERGE final em `CORE.*`

---

## Success Criteria

| Critério | Mensurável | Teste |
|----------|-----------|-------|
| DAG SAP roda sem erro e popula STAGING | `SELECT COUNT(*) FROM STAGING.SAP_CUSTOMERS` > 0 após run | AT-120 |
| DAG Oracle roda sem erro e popula STAGING | idem para `STAGING.ORACLE_*` | AT-121 |
| DAG HubSpot roda sem erro e popula STAGING | idem para `STAGING.HUBSPOT_*` | AT-122 |
| Stream captura mudanças em CORE.TRANSACTIONS | `SELECT COUNT(*) FROM CORE.TRANSACTIONS_STREAM` > 0 após INSERT/UPDATE | AT-123 |
| Task de CDC consome o Stream e atualiza o mart incrementalmente | Latência de refresh do `DT_REVENUE_MOVEMENT` cai vs. full recompute | AT-124 |
| Testes unitários dos 3 novos DAGs seguem o padrão de `test_pipelines.py` | pytest verde | AT-125 |

---

## Scope

### IN SCOPE — Sprint 4

**P0:**
- `airflow/dags/sap_ingest_dag.py` — customers, invoices, orders via OData
- `airflow/dags/oracle_ingest_dag.py` — tabelas equivalentes via oracledb/JDBC
- `snowflake/native_app/setup_script.sql` — `CREATE STREAM` em `CORE.TRANSACTIONS`, `CORE.CUSTOMERS`, `CORE.SUBSCRIPTIONS` + Task de consumo incremental para pelo menos 1 mart (`MART.DT_REVENUE_MOVEMENT`)

**P1:**
- `airflow/dags/hubspot_ingest_dag.py` — contacts, deals, companies
- Estender CDC incremental para `MART.DT_CUSTOMER_HEALTH` e `MART.DT_EXECUTIVE_KPIS`
- `tests/python/test_pipelines.py` — testes para os 3 novos DAGs, seguindo o padrão dos existentes

**P2:**
- Terraform: variáveis/secrets para credenciais SAP/Oracle/HubSpot
- Documentação de setup de credenciais por conector (README ou seção no CONTEXT.md)

### OUT OF SCOPE — Sprint 4

- Vertical Packs (financeiro, varejo, saúde) — Sprint 5+
- Feature Store / `AI.MODEL_OUTPUTS` — Sprint 5
- KBs adicionais (governance, business metrics) — Sprint 5
- Teste de integração real do Cortex Analyst contra conta live — Sprint 5
- Migração dos conectores existentes (Salesforce/Zendesk/Stripe) para CDC — ficam full-extraction por ora; só as tabelas core ganham Stream neste sprint

---

## Constraints

| Constraint | Detalhe |
|-----------|---------|
| Streams são consumer-side | `CREATE STREAM` vai no `setup_script.sql` (Native App), não em script de deploy direto — mesma lição do Sprint 2/3 sobre onde cada peça roda |
| Conectores continuam provider-side | Novos DAGs em `airflow/dags/`, executados no Airflow do provider — não no ambiente do consumer |
| Padrão de DAG existente | Seguir a estrutura de `salesforce_ingest_dag.py`/`stripe_ingest_dag.py`: TaskFlow API, `DEFAULT_ARGS` com retry, hook `SnowflakeHook`, MERGE idempotente |
| Credenciais via Airflow Variables | Mesma convenção dos 3 conectores existentes (`Variable.get(...)`), não hardcoded |
| Stream consumption window | Streams do Snowflake têm retenção de dados baseada em `DATA_RETENTION_TIME_IN_DAYS` da tabela de origem — Tasks de consumo devem rodar com frequência suficiente para não perder o offset |

---

## Dependencies

| Dependência | Sprint | Status |
|-------------|--------|--------|
| `STAGING` schema criado | Sprint 3 | ✅ |
| `CORE.TRANSACTIONS`, `CORE.CUSTOMERS`, `CORE.SUBSCRIPTIONS` existem | Sprint 1/2 | ✅ |
| Padrão de DAG Airflow (Salesforce/Zendesk/Stripe) | Sprint 2 | ✅ |
| CI/CD pipeline verde (deploy automatizado do Native App) | Sprint 3 | ✅ |

---

## Decisions Pre-made

**D1 — Staging por fonte:** cada conector escreve em seu próprio schema lógico dentro de `STAGING` (`STAGING.SAP_*`, `STAGING.ORACLE_*`, `STAGING.HUBSPOT_*`), evitando colisão de nomes entre fontes com objetos homônimos (ex: "customers" existe em SAP, Oracle e HubSpot).

**D2 — CDC começa pelas tabelas de maior volume:** `CORE.TRANSACTIONS` é priorizada para o primeiro Stream porque é a tabela que mais cresce e mais se beneficia de incremental vs. full recompute nos marts de revenue.

**D3 — Sem migração dos conectores existentes:** Salesforce/Zendesk/Stripe permanecem full-extraction neste sprint — migrá-los para CDC é decisão separada que exige revisar se as APIs de origem suportam webhooks/incremental (fora do escopo de "Streams do lado do consumer").
