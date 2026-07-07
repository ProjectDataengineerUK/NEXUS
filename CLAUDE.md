# NEXUS AI DataOps

> Plataforma horizontal de IA + Dados nativa em Snowflake — um "Enterprise AI Command Center" que transforma o Snowflake de cada cliente em um sistema inteligente de decisão, governança, automação e geração de receita. Distribuído via Snowflake Native App, sem mover dados para fora do ambiente do cliente. Foca em Customer & Revenue Intelligence como ponto de entrada, com expansão para Risk, Supply Chain, Compliance e Operations por packs verticais (financeiro, varejo, saúde, telecom, indústria, hotelaria, SaaS, automotivo).
>
> **Status:** MVP em hardening ativo — não é mais fase de conceito. Ver [`README.md`](README.md) para o estado real (features, quick start, limitações conhecidas).

---

## Stack

- **Plataforma principal:** Snowflake (Native App Framework, Snowpark, Cortex AI, Cortex Search, Cortex Analyst, Cortex Agents)
- **Frontend/UI:** Streamlit in Snowflake
- **ML/AI:** Snowpark ML, Cortex AI (LLMs), Document AI functions
- **Pipelines:** Dynamic Tables, Streams & Tasks, Snowpipe Streaming, dbt (planejado)
- **Ingestão:** Fivetran / Airbyte (planejado), COPY INTO, APIs (Salesforce, Zendesk, Stripe)
- **Orquestração externa:** Airflow / Dagster (planejado)
- **Segurança:** Masking Policies, Row Access Policies, Horizon Catalog, RBAC
- **Distribuição:** Snowflake Marketplace
- **Linguagem de aplicação:** Python (Snowpark, pipelines, modelos)
- **IaC/DevOps:** Terraform, GitHub Actions (planejado)
- **Armazenamento externo:** S3 / Azure Blob / GCS (fontes)

## Estrutura

```
NEXUS/
├── snowflake/           ← Native App: setup scripts (27), cortex (agents/semantic models/search), ML models, vertical packs
├── app/streamlit/        ← UI Streamlit-in-Snowflake (14 páginas)
├── dbt/                  ← dbt Core: staging → intermediate → marts
├── airflow/               ← DAGs de ingestão do lado do provider (Salesforce, Zendesk, Stripe, SAP, Oracle, HubSpot)
├── terraform/             ← IaC da infra do provider (databases, warehouses, rbac, security, monitoring)
├── api/                   ← FastAPI standalone (webhooks, integrações externas)
├── pipelines/kbs/         ← Pipeline de Knowledge Base Search
├── tests/                 ← pytest (Python) + asserções SQL
├── .github/workflows/     ← CI/CD: lint/test, terraform, dbt, deploy + release do Native App
├── CONTEXT.md             ← Conceito completo, roadmap e arquitetura (ChatGPT export)
├── ARCHITECTURE.md        ← Arquitetura técnica, diagramas, sprints
├── DEPLOYMENT.md          ← Guia de CI/CD e troubleshooting
├── CLOUD_STRATEGY.md      ← Estratégia multi-cloud
└── .claude/
    ├── settings.json
    ├── hooks/
    └── sdd/               ← Artefatos Spec-Driven Development (brainstorm/define/design/build/ship)
```

> Ver [`README.md`](README.md) para features, quick start e limitações conhecidas — este arquivo cobre convenções para agentes trabalhando no repo.

## Arquivos-chave

| Arquivo | Função |
|---------|--------|
| `README.md` | Estado real do projeto: features, quick start, arquitetura, limitações conhecidas |
| `CONTEXT.md` | Conceito completo do produto: ICP, módulos, roadmap, pricing, GTM |
| `ARCHITECTURE.md` | Arquitetura técnica detalhada, diagramas, sprints implementados |
| `snowflake.yml` | Definição do Native App para o Snowflake CLI (`snow app run`) |

## Convenções

- **Linter:** `ruff` (`ruff check app/streamlit/ snowflake/models/ snowflake/pipelines/ --select E,F,W,I --ignore E501`)
- **SAST:** `bandit` (não bloqueante em CI)
- **Formatter:** não configurado explicitamente (ruff cobre parte disso)
- **Testes:** `pytest` (`tests/python/`, gate de cobertura 50% sobre `snowflake/models`), asserções SQL em `tests/sql/` (ainda não passam de forma confiável), `dbt test` para os models

## Como rodar

```bash
# Instalar o Native App em dev via Snowflake CLI
snow app run --connection dev --force

# Rodar testes Python
pytest tests/python/ -v --cov=snowflake/models --cov-fail-under=50

# Rodar dbt
cd dbt && dbt deps && dbt run && dbt test
```

Ver [`README.md`](README.md#quick-start) para o guia completo de setup.

---

## Agentes recomendados (agentcode)

| Agente | Quando usar |
|--------|-------------|
| `@brainstorm-agent` | Explorar abordagens, refinar conceito, comparar alternativas |
| `@the-planner` | Criar plano de implementação detalhado por sprint |
| `@design-agent` | Arquitetura técnica, design de schemas, fluxos de dados |
| `@snowflake-data-engineer` | Implementar Dynamic Tables, Streams, Tasks, Snowpipe, Snowpark |
| `@snowflake-sql-expert` | Escrever SQL para schemas, marts e queries Snowflake |
| `@snowflake-cortex-expert` | Cortex AI, Cortex Search, Cortex Analyst, Cortex Agents |
| `@snowflake-governance-expert` | RBAC, masking policies, row access policies, PII, compliance |
| `@snowflake-cost-optimizer` | Otimizar créditos Snowflake, warehouse sizing, cache |
| `@python-developer` | Pipelines de ingestão, Snowpark Python, modelos de ML |
| `@schema-designer` | Modelagem dimensional, data vault, Universal Enterprise Data Model |
| `@lakeflow-architect` | Medalllion architecture, Bronze/Silver/Gold com DLT |
| `@dbt-specialist` | Transformações com dbt sobre Snowflake |
| `@security-reviewer` | Revisar segurança de código, RBAC e governança |
| `@code-reviewer` | Revisão de qualidade em todo código implementado |

## Comandos úteis

| Comando | Quando usar |
|---------|-------------|
| `/brainstorm` | Explorar um novo módulo, vertical ou abordagem técnica |
| `/define` | Capturar requisitos formais de um módulo (ex: Document Intelligence) |
| `/design` | Criar arquitetura técnica de um sprint ou componente |
| `/build` | Executar implementação a partir de um design aprovado |
| `/sql` | Escrever ou otimizar queries Snowflake |
| `/workflow` | Criar ou revisar workflows com LLMs e agentes |
| `/status` | Ver status geral do projeto e próximos passos |
| `/preflight` | Checar saúde do projeto antes de implementar |

---

_Gerado por `/start` em 2026-06-15._
