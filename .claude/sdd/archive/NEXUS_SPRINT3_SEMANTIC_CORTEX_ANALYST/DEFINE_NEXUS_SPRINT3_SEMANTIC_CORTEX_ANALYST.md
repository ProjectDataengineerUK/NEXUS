# DEFINE — NEXUS Sprint 3: Semantic Models, Cortex Analyst & Multi-org

**Feature:** NEXUS_SPRINT3_SEMANTIC_CORTEX_ANALYST  
**Phase:** 1 — Define  
**Date:** 2026-06-19  
**Status:** Draft  
**Clarity Score:** 14/15  

---

## Problem Statement

Sprint 2 entregou o Operations Agent (`operations_agent.yaml`) e duas novas páginas Streamlit (`11_Sales_Intelligence.py`, `12_Operations_Intelligence.py`), mas deixou três blockers que impedem o deploy funcional:

1. **`operations_model.yaml` não existe** — o Operations Agent referencia `@NEXUS_APP.CONFIG.NEXUS_STAGE/semantic_models/operations_model.yaml` que nunca foi criado. O agente falha ao tentar usar Cortex Analyst.
2. **Cortex Analyst não disponível nas páginas de domínio** — `11_Sales_Intelligence.py` e `12_Operations_Intelligence.py` entregam métricas mas sem NL→SQL; o usuário não consegue fazer perguntas em linguagem natural nessas páginas.
3. **Demo data de um único org** — todos os 10 clientes de demo usam `ORG-DEMO-001`, impossibilitando validar o `RAP_ORG_ISOLATION` com múltiplos tenants; o teste AT-102 é manual e não pode ser automatizado.

Secundário: `STAGING` schema não existe formalmente no setup_script — os DAGs Airflow criam tabelas `STAGING.*` no runtime com `CREATE TABLE IF NOT EXISTS`, o que falha se o schema não existir.

---

## Users

| Persona | Dor | Prioridade |
|---------|-----|-----------|
| **Usuário final (analista)** | Quer perguntar "quantos tickets urgentes esta semana?" em linguagem natural na página de Operações, não ficar construindo filtros | P0 |
| **Usuário final (gerente de vendas)** | Quer perguntar "qual cliente tem maior oportunidade de upsell?" na página de Sales sem saber SQL | P0 |
| **Provider (nós)** | Operations Agent não funciona em prod — blocker de demo | P0 |
| **QA / CI** | Não consegue testar RAP isolation com demo data de um único org | P1 |
| **Provider (pipeline)** | DAG Airflow falha se schema STAGING não existir previamente | P1 |

---

## Goals

1. **Desbloquear Operations Agent** — criar `operations_model.yaml` cobrindo CORE.TICKETS, CORE.INTERACTIONS e MART.DT_CUSTOMER_HEALTH; corrigir path no agent YAML
2. **NL→SQL em domínios** — adicionar widget Cortex Analyst à página 12 (Operações) e 11 (Sales) com modelos semânticos adequados
3. **`revenue_opportunity_model.yaml`** — modelo semântico novo para MART.REVENUE_OPPORTUNITY_SCORE + MART.DT_REVENUE_MOVEMENT + CORE.PRODUCTS; habilita Sales Agent e página 11
4. **Multi-org demo** — adicionar `ORG-DEMO-002` com 3+ clientes no setup_script; mapear novo usuário em ORG_USER_MAP; permitir AT-102 automatizado
5. **STAGING schema formal** — `CREATE SCHEMA IF NOT EXISTS STAGING` no setup_script
6. **Upload script** — `scripts/upload_semantic_models.sh` via `snow sql -q "PUT file://..."` para subir YAMLs ao `@CORE.SEMANTIC_STAGE`
7. **Routing multi-modelo em AI Chat** — 3_AI_Chat.py deve rotear entre modelos (executive/revenue/operations/customer) com seletor de domínio

---

## Success Criteria

| Critério | Mensurável | Teste |
|----------|-----------|-------|
| Operations Agent responde sem erro | Chamada à API Cortex Agents retorna `{"status": "success"}` | AT-110 |
| Cortex Analyst responde query em PT em 3_AI_Chat.py domínio=operations | SQL gerado referencia CORE.TICKETS ou CORE.INTERACTIONS | AT-111 |
| Página 11 tem widget NL→SQL | Campo de texto + resultado SQL visível na UI | Manual |
| Página 12 tem widget NL→SQL | idem para operações | Manual |
| Demo data tem 2 org_ids distintos | `SELECT COUNT(DISTINCT org_id) FROM CORE.CUSTOMERS` = 2 | AT-112 |
| RAP isola orgs | Usuário ORG-DEMO-002 não vê clientes de ORG-DEMO-001 | AT-102 (agora automatizável) |
| STAGING schema existe | `SELECT * FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = 'STAGING'` | AT-113 |
| upload_semantic_models.sh completa sem erro | Exit code 0, YAMLs visíveis via `LIST @CORE.SEMANTIC_STAGE` | AT-114 |

---

## Acceptance Tests

### AT-110 — operations_model.yaml acessível e válido
```
DADO que setup_script foi executado e upload_semantic_models.sh rodou
QUANDO LIST @CORE.SEMANTIC_STAGE é executado
ENTÃO operations_model.yaml aparece na listagem com tamanho > 0
```

### AT-111 — Cortex Analyst NL→SQL com operations_model
```
DADO que operations_model.yaml está no stage
QUANDO o Cortex Analyst recebe "quantos tickets estão abertos com prioridade urgente?"
ENTÃO a resposta contém SQL referenciando CORE.TICKETS com filtro status='open' AND priority='urgent'
```

### AT-112 — Demo data multi-org
```
DADO que setup_script v3.0.0 foi executado
QUANDO SELECT COUNT(DISTINCT org_id) FROM CORE.CUSTOMERS
ENTÃO resultado = 2 (ORG-DEMO-001 e ORG-DEMO-002)
```

### AT-113 — STAGING schema existe
```
DADO setup_script executado
QUANDO SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = 'STAGING'
ENTÃO retorna 1 linha
```

### AT-114 — Semantic models no stage
```
DADO upload_semantic_models.sh executado com credenciais válidas
QUANDO LIST @NEXUS_APP.CORE.SEMANTIC_STAGE
ENTÃO listing contém: executive_kpis.yaml, nexus_revenue.yaml, customer_360.yaml,
      operations_model.yaml, revenue_opportunity_model.yaml
```

### AT-115 — Multi-model routing em AI Chat
```
DADO que o usuário seleciona domínio "Operações" em 3_AI_Chat.py
QUANDO digita "qual o tempo médio de resolução de tickets?"
ENTÃO a chamada usa semantic_model_file apontando para operations_model.yaml
```

---

## Scope

### IN SCOPE — Sprint 3

**P0 — Blockers (deploy-blocking):**
- `snowflake/cortex/semantic_models/operations_model.yaml` — novo, cobre TICKETS + INTERACTIONS + DT_CUSTOMER_HEALTH
- `snowflake/cortex/semantic_models/revenue_opportunity_model.yaml` — novo, cobre REVENUE_OPPORTUNITY_SCORE + DT_REVENUE_MOVEMENT + PRODUCTS
- Corrigir `operations_agent.yaml` — atualizar path para `@NEXUS_APP.CORE.SEMANTIC_STAGE/operations_model.yaml`
- `scripts/upload_semantic_models.sh` — PUT todos os 5 YAMLs ao `@CORE.SEMANTIC_STAGE`
- `setup_script.sql` — adicionar `CREATE SCHEMA IF NOT EXISTS STAGING` + GRANTS

**P1 — High value:**
- `setup_script.sql` — adicionar demo data ORG-DEMO-002 (3 customers, tickets, interactions, churn scores) + ORG_USER_MAP entry para NEXUS_ANALYST_2
- `app/streamlit/pages/12_Operations_Intelligence.py` — widget NL→SQL usando operations_model
- `app/streamlit/pages/11_Sales_Intelligence.py` — widget NL→SQL usando revenue_opportunity_model
- `app/streamlit/pages/3_AI_Chat.py` — seletor de domínio (Executive / Revenue / Operations / Customer) com routing de semantic_model_file
- `app/streamlit/utils/cortex_analyst.py` — helper reutilizável `ask_analyst(question, model_file) -> (sql, results)`
- `snowflake/cortex/semantic_models/customer_360.yaml` — update para incluir CORE.INTERACTIONS (nova tabela do Sprint 2)
- `tests/sql/test_semantic_models.sql` — AT-110/112/113/114
- `tests/python/test_cortex_analyst.py` — validação estrutural dos YAMLs (tabelas, measures, dimensions)

**P2 — Nice to have:**
- `setup_script.sql` — `AI.AGENT_MEMORY` table (multi-turn agent state)
- `setup_script.sql` — `AI.EMBEDDINGS` table formal (estava só em scripts standalone)
- `terraform/modules/monitoring/main.tf` — adicionar alerta de Cortex Analyst latency

### OUT OF SCOPE — Sprint 3

- Conectores adicionais (SAP, Oracle, HubSpot) — Sprint 4+
- CDC com Streams sobre tabelas do consumer — Sprint 4
- Vertical Packs (financeiro, varejo, saúde) — Sprint 5+
- `AI.MODEL_OUTPUTS` / Feature Store — Sprint 4
- Snowflake CLI / `snow app run` no CI — Sprint 4
- KBs adicionais (governance, business metrics) — Sprint 4
- Testes E2E com Playwright no Streamlit

---

## Constraints

| Constraint | Detalhe |
|-----------|---------|
| Native App | `scripts/upload_semantic_models.sh` roda no **provider**, não via setup_script (PUT não é suportado em setup_script do Native App) |
| Stage path | Agents existentes usam `@NEXUS_APP.CORE.SEMANTIC_STAGE/` — manter esse path; só o operations_agent usava path errado (`CONFIG.NEXUS_STAGE`) |
| Cortex Analyst modelo | Manter `mistral-large2` por padrão (já usado em 3_AI_Chat.py) |
| Idempotência | Demo data ORG-DEMO-002 deve usar MERGE INTO como os dados existentes |
| Semantic model spec | YAMLs devem seguir Snowflake Cortex Analyst spec: `name`, `description`, `tables[].base_table`, `tables[].dimensions`, `tables[].measures` |
| Clareza de nome | Semantic model `revenue_opportunity_model` ≠ `nexus_revenue` existente — ambos coexistem para domínios diferentes |

---

## Dependencies

| Dependência | Sprint | Status |
|-------------|--------|--------|
| `CORE.SEMANTIC_STAGE` criado em setup_script | Sprint 1 | ✅ linha 388 |
| `CORE.TICKETS`, `CORE.INTERACTIONS` existem | Sprint 2 | ✅ |
| `MART.DT_CUSTOMER_HEALTH`, `MART.REVENUE_OPPORTUNITY_SCORE` existem | Sprint 2 | ✅ |
| `KBS.KB_SEARCH_SERVICE` para operations_agent | Sprint 2 | ✅ |
| `RAP_ORG_ISOLATION` aplicada em todas as tabelas | Sprint 2 | ✅ |

---

## File Manifest (Preview)

| # | File | Action | Priority |
|---|------|--------|----------|
| 1 | `snowflake/cortex/semantic_models/operations_model.yaml` | Create | P0 |
| 2 | `snowflake/cortex/semantic_models/revenue_opportunity_model.yaml` | Create | P0 |
| 3 | `snowflake/cortex/agents/operations_agent.yaml` | Modify (fix path) | P0 |
| 4 | `scripts/upload_semantic_models.sh` | Create | P0 |
| 5 | `snowflake/native_app/setup_script.sql` | Modify (STAGING + demo ORG-002) | P0+P1 |
| 6 | `app/streamlit/utils/cortex_analyst.py` | Create | P1 |
| 7 | `app/streamlit/pages/3_AI_Chat.py` | Modify (multi-model routing) | P1 |
| 8 | `app/streamlit/pages/11_Sales_Intelligence.py` | Modify (NL→SQL widget) | P1 |
| 9 | `app/streamlit/pages/12_Operations_Intelligence.py` | Modify (NL→SQL widget) | P1 |
| 10 | `snowflake/cortex/semantic_models/customer_360.yaml` | Modify (add INTERACTIONS) | P1 |
| 11 | `tests/sql/test_semantic_models.sql` | Create | P1 |
| 12 | `tests/python/test_cortex_analyst.py` | Create | P1 |
| 13 | `setup_script.sql` (AI.AGENT_MEMORY, AI.EMBEDDINGS) | Modify | P2 |

---

## Decisions Pre-made

**D1 — Stage path canônico:** `@NEXUS_APP.CORE.SEMANTIC_STAGE/` para todos os semantic models. Corrigir `operations_agent.yaml` de `CONFIG.NEXUS_STAGE` → `CORE.SEMANTIC_STAGE`.

**D2 — upload via shell, não setup_script:** PUT de arquivos locais para internal stage não é suportado no setup_script do Native App. Script separado `upload_semantic_models.sh` usa `snowsql -q "PUT file://..."` e é executado pelo provider como passo de bootstrap após `snow app run`.

**D3 — Multi-model routing via seletor:** 3_AI_Chat.py ganha um `st.selectbox` de domínio que troca o `semantic_model_file` usado na chamada — sem mudar a arquitetura do cliente Cortex.

**D4 — `revenue_opportunity_model` é separado de `nexus_revenue`:** `nexus_revenue.yaml` já existe e serve os agentes Executive/Revenue/Customer. O novo modelo cobre as tabelas novas do Sprint 2 (`MART.REVENUE_OPPORTUNITY_SCORE`, `MART.DT_REVENUE_MOVEMENT`) que não estão no modelo legado.

**D5 — Demo ORG-DEMO-002 com perfil contrastante:** 3 clientes SMB em LATAM, todos com churn_risk alto, para facilitar visualização do RAP em ação — fácil de distinguir de ORG-DEMO-001 (Enterprise/Mid-Market).
