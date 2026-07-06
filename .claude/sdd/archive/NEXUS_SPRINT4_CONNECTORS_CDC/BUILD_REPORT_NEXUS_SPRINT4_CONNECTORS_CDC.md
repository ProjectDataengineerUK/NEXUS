# BUILD REPORT — NEXUS Sprint 4: Conectores Adicionais + CDC via Streams

**Feature:** NEXUS_SPRINT4_CONNECTORS_CDC
**Phase:** 3 — Build
**Build Date:** 2026-07-06
**Status:** ✅ Completo

---

## Escopo entregue

Todos os itens P0/P1/P2 do DEFINE foram implementados e validados por teste automatizado.

### P0 — Blockers
| Item | Arquivo | Status |
|------|---------|--------|
| Conector SAP (OData: Customers, Invoices, Orders) | `airflow/dags/sap_ingest_dag.py` | ✅ |
| Conector Oracle (oracledb thin mode) | `airflow/dags/oracle_ingest_dag.py` | ✅ |
| Streams + Tasks de CDC em `CORE.TRANSACTIONS`/`CORE.CUSTOMERS` | `setup_script.sql` (redesenhado para STAGING→CORE, ver Decision 4) | ✅ |

### P1 — High value
| Item | Arquivo | Status |
|------|---------|--------|
| Conector HubSpot (contacts, deals, companies) | `airflow/dags/hubspot_ingest_dag.py` | ✅ |
| CDC estendido para todos os 9 objetos staged (não só o mínimo do DEFINE) | `setup_script.sql` | ✅ |
| Testes dos 3 novos DAGs | `tests/python/test_pipelines.py` (`TestSAPDAG`, `TestOracleDAG`, `TestHubSpotDAG`) | ✅ |

### P2 — Nice to have
| Item | Status |
|------|--------|
| Documentação de credenciais por conector | ✅ `airflow/README.md` |
| Terraform para secrets do Airflow | ⏭️ Não aplicável — nenhum dos 6 conectores (incluindo os 3 do Sprint 2) usa Terraform para variáveis do Airflow; documentação via README é a entrega consistente (ver Decision abaixo) |

---

## Decisão de design que corrigiu o DEFINE

O DEFINE original (AT-123/AT-124) previa Streams sobre `CORE.TRANSACTIONS` alimentando `MART.DT_REVENUE_MOVEMENT`. Isso foi corrigido no DESIGN (Decision 4): **Dynamic Tables já fazem refresh incremental nativo** — criar Stream/Task escrevendo na mesma tabela que o motor de DT gerencia geraria conflito de escrita. O CDC foi redesenhado para ficar entre `STAGING.<fonte>_*` e `CORE.*`, onde de fato reduz custo (evita reprocessar toda a staging a cada run do DAG) sem competir com o motor de Dynamic Tables.

---

## Arquitetura final

```
Airflow (extract + load raw JSON) → STAGING.<FONTE>_<OBJETO>
                                          │ Stream (APPEND_ONLY)
                                          ▼
                            Task (WHEN SYSTEM$STREAM_HAS_DATA)
                                          │ MERGE incremental
                                          ▼
                                    CORE.CUSTOMERS / CORE.TRANSACTIONS / CORE.ACCOUNTS
                                          │ (mecanismo nativo do Snowflake)
                                          ▼
                            MART.DT_* (Dynamic Tables, refresh incremental automático)
```

**9 objetos cobertos, com CDC completo (Stream + Task) em todos:**

| Fonte | Objeto | Task | Destino CORE |
|-------|--------|------|---------------|
| SAP | Customers | `TASK_MERGE_SAP_CUSTOMERS` | `CORE.CUSTOMERS` |
| SAP | Invoices | `TASK_MERGE_SAP_INVOICES` | `CORE.TRANSACTIONS` |
| SAP | Orders | `TASK_MERGE_SAP_ORDERS` | `CORE.TRANSACTIONS` |
| Oracle | Customers | `TASK_MERGE_ORACLE_CUSTOMERS` | `CORE.CUSTOMERS` |
| Oracle | Orders | `TASK_MERGE_ORACLE_ORDERS` | `CORE.TRANSACTIONS` |
| Oracle | Invoices | `TASK_MERGE_ORACLE_INVOICES` | `CORE.TRANSACTIONS` |
| HubSpot | Contacts | `TASK_MERGE_HUBSPOT_CONTACTS` | `CORE.CUSTOMERS` |
| HubSpot | Deals | `TASK_MERGE_HUBSPOT_DEALS` | `CORE.TRANSACTIONS` |
| HubSpot | Companies | `TASK_MERGE_HUBSPOT_COMPANIES` | `CORE.ACCOUNTS` |

Todos os IDs prefixados por fonte (`SAP-`, `ORCL-`, `HS-`) para evitar colisão de namespace entre fontes diferentes que reciclam os mesmos IDs internos.

---

## Métricas

| Métrica | Valor |
|---------|-------|
| Arquivos criados | 5 (3 DAGs + README + test_cdc_streams.sql) |
| Arquivos modificados | 3 (setup_script.sql, requirements.txt, test_pipelines.py) |
| Linhas adicionadas | ~870 |
| Novas tabelas STAGING | 9 |
| Novos Streams | 9 |
| Novas Tasks de CDC | 9 |
| Testes novos (`test_pipelines.py`) | 20 (`TestSAPDAG`, `TestOracleDAG`, `TestHubSpotDAG`) |
| Testes totais na suíte Python | 134 (100% passando) |

---

## Validação

- ✅ `pytest tests/python/` (suíte completa) — 134/134 passed
- ✅ Sintaxe Python dos 3 novos DAGs validada (`py_compile`)
- ✅ Balanceamento de dollar-quotes no `setup_script.sql` (102, par)
- ✅ CI `Lint + Unit Tests` — verde
- ✅ CI `dbt compile (dry run)` — verde
- ✅ CI `Deploy artefatos (dev)` — verde
- ✅ CI `Native App — dev` (`snow app run --force`) — verde nos dois commits do build (inicial e do CDC completo), sem nenhum round de correção necessário
- ⏭️ Execução real dos DAGs contra fontes SAP/Oracle/HubSpot vivas — não verificável sem credenciais reais; a estrutura e o MERGE incremental foram validados via instalação do setup_script no Snowflake, não via execução ponta-a-ponta do Airflow
