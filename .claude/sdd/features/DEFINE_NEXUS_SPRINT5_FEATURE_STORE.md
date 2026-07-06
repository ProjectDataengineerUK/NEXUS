# DEFINE — NEXUS Sprint 5: Feature Store & AI.MODEL_OUTPUTS

**Feature:** NEXUS_SPRINT5_FEATURE_STORE
**Phase:** 1 — Define
**Date:** 2026-07-06
**Status:** Draft

---

## Problem Statement

Cada modelo de ML do NEXUS resolve features e persiste saídas de forma isolada e inconsistente:

1. **Sem tabela unificada de outputs** — `AI.CHURN_SCORES`, `AI.REVENUE_FORECAST`, `AI.ANOMALY_ALERTS`, `AI.RECOMMENDATIONS` têm schemas totalmente diferentes entre si. Não existe uma forma de perguntar "quais previsões de IA existem para o cliente X" sem fazer 4 joins com schemas distintos.
2. **Dois modelos órfãos** — `snowflake/models/anomaly_model.py` (Cortex ML `AnomalyDetector`) e `snowflake/models/forecast_model.py` (Cortex ML `Forecaster`) existem como código fonte completo, e suas tabelas de destino (`AI.ANOMALY_ALERTS`, `AI.REVENUE_FORECAST`) já existem no `setup_script.sql` — mas **nenhum dos dois está conectado a uma stored procedure ou Task**. Eles nunca rodam em produção; as tabelas ficam permanentemente vazias.
3. **Features recalculadas ad-hoc por modelo** — `churn_model.py` lê `FEATURE_COLS` diretamente de `MART.CUSTOMER_360` (uma view já bem centralizada para métricas de cliente). Mas não há equivalente para features de nível "org" (ex: métricas agregadas usadas por forecast/anomaly) nem um contrato versionado de quais features cada modelo usa — se `CUSTOMER_360` mudar de shape, todos os modelos quebram silenciosamente.

---

## Users

| Persona | Dor | Prioridade |
|---------|-----|-----------|
| **Provider (ML/plataforma)** | Precisa adicionar um novo modelo (ex: upsell propensity) e reescreve toda a lógica de feature engineering do zero | P0 |
| **Cliente (Executive/Data Steward Agent)** | Quer perguntar "o que a IA já disse sobre este cliente/métrica" sem saber em qual tabela específica está | P0 |
| **Provider (operação)** | `AI.REVENUE_FORECAST` e `AI.ANOMALY_ALERTS` existem no schema mas estão sempre vazias — nenhum alerta de anomalia real nunca chegou a ser gerado | P0 |
| **Cientista de dados (futuro)** | Sem features versionadas, não há como saber se um modelo antigo usou uma definição de feature diferente da atual | P1 |

---

## Goals

1. **`AI.MODEL_OUTPUTS`** — tabela unificada (schema flexível via VARIANT) para qualquer saída de modelo ML, complementando (não substituindo) as tabelas específicas existentes
2. **Conectar os modelos órfãos** — criar `CORE.SP_RUN_ANOMALY_DETECTION` e `CORE.SP_RUN_FORECAST`, com Tasks agendadas, replicando o padrão já usado para `SP_RUN_CHURN_PIPELINE` (inline no setup_script, sem IMPORTS — ver Sprint 3)
3. **Feature Store canônico** — uma Dynamic Table (`MART.DT_FEATURE_STORE`) que materializa as features de nível "org" reutilizáveis entre forecast/anomaly (receita diária, contagem de tickets, health score médio), com refresh automático
4. **Dual-write para compatibilidade** — os 4 modelos (churn, forecast, anomaly, recommendation) escrevem tanto na tabela específica quanto em `AI.MODEL_OUTPUTS`, sem quebrar consumidores existentes (Streamlit pages, agentes Cortex)

---

## Success Criteria

| Critério | Mensurável | Teste |
|----------|-----------|-------|
| `AI.MODEL_OUTPUTS` existe com schema unificado | `DESCRIBE TABLE AI.MODEL_OUTPUTS` retorna colunas esperadas | AT-130 |
| `SP_RUN_ANOMALY_DETECTION` executa sem erro | `CALL CORE.SP_RUN_ANOMALY_DETECTION()` retorna string `OK:...` | AT-131 |
| `SP_RUN_FORECAST` executa sem erro | `CALL CORE.SP_RUN_FORECAST()` retorna string `OK:...` | AT-132 |
| Tasks de anomaly/forecast agendadas | `SHOW TASKS` lista `TASK_RUN_ANOMALY_DETECTION` e `TASK_RUN_FORECAST` | AT-133 |
| `MART.DT_FEATURE_STORE` existe e tem linhas por org | `SELECT COUNT(DISTINCT org_id) FROM MART.DT_FEATURE_STORE` >= 1 | AT-134 |
| Os 4 modelos escrevem em `AI.MODEL_OUTPUTS` | `SELECT COUNT(DISTINCT model_name) FROM AI.MODEL_OUTPUTS` = 4 após execução de todos | AT-135 |
| Tabelas específicas continuam funcionando (compat) | Queries existentes em `11_Sales_Intelligence.py`/`12_Operations_Intelligence.py` sobre `AI.CHURN_SCORES` etc. não quebram | Manual/regressão |

---

## Scope

### IN SCOPE — Sprint 5

**P0 — Blockers:**
- `AI.MODEL_OUTPUTS` — nova tabela: `output_id, org_id, model_name, model_version, entity_id, entity_type, output_type, output_value VARIANT, confidence_score, generated_at`
- `CORE.SP_RUN_ANOMALY_DETECTION` — inline no setup_script (espelha `snowflake/models/anomaly_model.py`), escreve em `AI.ANOMALY_ALERTS` + `AI.MODEL_OUTPUTS`
- `CORE.SP_RUN_FORECAST` — inline no setup_script (espelha `snowflake/models/forecast_model.py`), escreve em `AI.REVENUE_FORECAST` + `AI.MODEL_OUTPUTS`
- `TASK_RUN_ANOMALY_DETECTION` e `TASK_RUN_FORECAST` — Tasks diárias, mesmo padrão tolerante de RESUME do Sprint 3/4
- Dual-write em `SP_RUN_CHURN_PIPELINE` (já existente) — também grava em `AI.MODEL_OUTPUTS`

**P1 — High value:**
- `MART.DT_FEATURE_STORE` — Dynamic Table com features de nível org (revenue diário, contagem/severidade de tickets, health score médio, churn risk médio) para servir forecast/anomaly sem cada um recalcular do zero
- Dual-write em `RECOMMENDATIONS` (recommendation_model.py) para `AI.MODEL_OUTPUTS`
- `tests/python/test_model_outputs.py` — testes estruturais dos novos SPs/tabelas, seguindo o padrão de `test_cortex_analyst.py`/`test_pipelines.py`
- `tests/sql/test_model_outputs.sql` — acceptance tests AT-130 a AT-135

**P2 — Nice to have:**
- View `AI.V_LATEST_MODEL_OUTPUTS` — última saída de cada modelo por entidade (facilita consumo pelos agentes Cortex)
- Widget em `3_AI_Chat.py` ou nova página mostrando outputs recentes de todos os modelos

### OUT OF SCOPE — Sprint 5

- Novo modelo de ML (ex: upsell propensity) — usar o Feature Store é o objetivo, não criar um consumidor novo
- Feature versioning formal (schema registry) — Sprint 6+, se a dor aparecer
- Retreinamento automático de modelos — fora de escopo, cadência de treino continua manual/agendada como está

---

## Constraints

| Constraint | Detalhe |
|-----------|---------|
| Sem IMPORTS em schema não-versionado | Mesma restrição do Sprint 3 — `SP_RUN_ANOMALY_DETECTION`/`SP_RUN_FORECAST` devem ser inline no setup_script, não referenciar `snowflake/models/*.py` via IMPORTS |
| Compatibilidade retroativa | Tabelas específicas (`AI.CHURN_SCORES` etc.) não podem ser removidas nem ter schema quebrado — só ganham dual-write |
| `AI.MODEL_OUTPUTS.output_value` é VARIANT | Schema flexível é intencional — cada modelo tem outputs de shape diferente; a padronização está nas colunas de metadado (org_id, model_name, entity_id), não no payload |
| Cortex ML `Forecaster`/`AnomalyDetector` exigem `snowflake-ml-python` | Já é dependência de `SP_RUN_CHURN_PIPELINE` — sem custo adicional de PACKAGES |

---

## Dependencies

| Dependência | Sprint | Status |
|-------------|--------|--------|
| Padrão de procedure inline (sem IMPORTS) | Sprint 3 | ✅ |
| Padrão de Task tolerante (RESUME com EXCEPTION) | Sprint 3 | ✅ |
| `AI.ANOMALY_ALERTS`, `AI.REVENUE_FORECAST` já existem | Sprint 1/2 | ✅ (vazias até este sprint) |
| `MART.CUSTOMER_360` (fonte de features de cliente) | Sprint 1/2 | ✅ |
| CI/CD pipeline verde | Sprint 3 | ✅ |

---

## Decisions Pre-made

**D1 — `AI.MODEL_OUTPUTS` complementa, não substitui:** as tabelas específicas continuam sendo a fonte primária para cada domínio (Streamlit pages já fazem queries otimizadas contra elas). `AI.MODEL_OUTPUTS` serve consultas cross-model, não substitui os joins existentes.

**D2 — Feature Store começa no nível "org", não "customer":** `MART.CUSTOMER_360` já cobre bem features por cliente (usado pelo churn model). O gap real é em features agregadas por org (usadas por forecast/anomaly) — `MART.DT_FEATURE_STORE` foca nisso primeiro; extensão para nível customer fica para se houver necessidade real de um segundo modelo customer-level além do churn.

**D3 — Prioridade em destravar os modelos órfãos, não em arquitetura de feature store elaborada:** dado que `anomaly_model.py`/`forecast_model.py` já têm lógica completa e nunca rodaram, conectá-los é P0 — tem impacto direto e imediato (2 tabelas que finalmente populam). O Feature Store em si (`DT_FEATURE_STORE`) é P1, um passo de consolidação depois que os modelos já estão rodando.
