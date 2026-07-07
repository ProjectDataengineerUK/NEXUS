# NEXUS AI DataOps

> Enterprise AI Command Center nativo em Snowflake — transforma o Snowflake que o cliente já tem em um sistema de decisão e ação, sem mover dado para fora do ambiente dele.

Distribuído como **Snowflake Native App** (Snowflake Marketplace), NEXUS combina Cortex Agents, Cortex Search e Cortex Analyst com uma camada de dados governada (RBAC, Row Access Policy multi-tenant, Dynamic Tables) para dar a times de Revenue, Customer Success, Risco e Data Governance respostas em linguagem natural sobre os próprios dados — e ações recomendadas a partir delas.

**Status:** MVP em hardening ativo. Não é conceito — há uma arquitetura real rodando (6 schemas, 27 migrations, RBAC + Row Access Policy multi-tenant, 6 Cortex Agents, 5 semantic models, 3 Cortex Search services, UI Streamlit com 14 páginas) e CI/CD que builda, testa e instala o Native App de verdade a cada push em `main`. Também não é produto v1.0 polido: testes de asserção SQL ainda não passam de forma confiável, o gate de cobertura cobre só `snowflake/models` (50%), e alguns pipelines de ingestão externa (Salesforce/Zendesk/Stripe) têm código mas não trigger automático. Veja [Known Limitations](#known-limitations).

---

## Overview

Empresas que já centralizaram dados no Snowflake ainda dependem de ferramentas de BI, RPA e "IA pontual" desconectadas para transformar esses dados em decisão. O dado é governado, mas não é *acionado*. O NEXUS resolve isso rodando **dentro** do Snowflake do cliente como Native App: zero movimentação de dado para fora do ambiente, RBAC e Row Access Policy nativos do Snowflake, e uma camada de agentes de IA (Cortex Agents) especializados por função de negócio.

Ponto de entrada: **Customer & Revenue Intelligence** (churn, ARR/MRR, health score, oportunidades de expansão). Expansão planejada por packs verticais — os scripts SQL para 6 verticais (financial services, retail, healthcare, telecom, industrial, hospitality) já existem em `snowflake/verticals/`, ainda sem UI dedicada.

## Features

- **6 Cortex Agents especializados** — `executive_agent` (C-level), `customer_agent` (CS/CSM), `revenue_agent` (CRO/RevOps), `risk_agent` (Legal/Compliance), `data_steward_agent` (Data Eng/Governance), `operations_agent` (ops/SLA) — cada um com guardrails, grounding obrigatório e tools próprios.
- **Cortex Analyst (NL→SQL)** sobre 5 Semantic Models: Customer 360, Executive KPIs, Revenue, Operations, Revenue Opportunity.
- **Cortex Search** sobre 3 índices: documentos gerais, contratos (isolado por latência/acesso), e uma Knowledge Base unificada (KBS).
- **Multi-tenancy real** via `org_id` + Row Access Policy (`GOVERNANCE.RAP_ORG_ISOLATION`) — cada instalação isola os dados do consumer sem custom code.
- **UI Streamlit de 14 páginas**: Executive Command, Customer 360, AI Chat, Document Intelligence, Recommendations/Action Center, Data Quality, Admin, Agent Workbench, Sales/Operations Intelligence, Data Product Catalog, Setup Wizard.
- **Pipeline de dados completo**: Dynamic Tables + Streams/Tasks para CDC, dbt (16 models: staging → intermediate → marts), Snowpark ML (churn, forecast, anomaly, recommendation).
- **CI/CD real**: lint (ruff), secret scan (gitleaks), SAST (bandit), testes (pytest com gate de cobertura), deploy automático (`snow app run`) e release versionado do Native App via tags.

## Quick Start

### Prerequisites

- Conta Snowflake **Enterprise Edition** com Cortex AI habilitado
- [Snowflake CLI](https://docs.snowflake.com/en/developer-guide/snowflake-cli/index) (`snow`) ≥ 3.5
- Python 3.10+ (para pipelines, testes e Snowpark ML)
- Role com privilégios para criar Native App packages (tipicamente `ACCOUNTADMIN` em dev)

### Installation (dev)

```bash
git clone <repo-url>
cd NEXUS

# Autenticar o Snowflake CLI (connection "dev" definida no seu config.toml)
snow connection add dev

# Instalar o Native App localmente a partir do snowflake.yml
snow app run --connection dev --force
```

Isso builda os artifacts declarados em `snowflake.yml` (setup script, manifest, Streamlit app, semantic models, agents, stored procedures, Snowpark ML) e instala a aplicação `NEXUS_AI_DATAOPS_TEST` na conta.

### Basic Usage

Após a instalação, conceda as application roles ao seu usuário (ver `snowflake/native_app/readme.md` para o texto completo voltado ao consumer final):

```sql
GRANT APPLICATION ROLE NEXUS_AI_DATAOPS_TEST.NEXUS_ADMIN TO ROLE <sua_role>;
```

Abra o Streamlit `CORE.NEXUS_UI` dentro da aplicação instalada — a página `0_Setup.py` conduz o onboarding (mapeamento de tabelas via `references:` do manifest, configuração de org, credenciais de API).

## Documentation

| Tópico | Arquivo |
| ------ | ------- |
| Conceito completo do produto (ICP, verticais, roadmap, pricing, GTM) | [`CONTEXT.md`](CONTEXT.md) |
| Arquitetura técnica, diagrama, sprints, warehouse sizing | [`ARCHITECTURE.md`](ARCHITECTURE.md) |
| Estratégia multi-cloud (AWS/GCP/Azure) | [`CLOUD_STRATEGY.md`](CLOUD_STRATEGY.md) |
| Guia de CI/CD, secrets do GitHub, troubleshooting de deploy | [`DEPLOYMENT.md`](DEPLOYMENT.md) |
| README voltado ao consumer final (Marketplace) | [`snowflake/native_app/readme.md`](snowflake/native_app/readme.md) |
| DAGs Airflow do lado do provider (ingestão externa) | [`airflow/README.md`](airflow/README.md) |
| Convenções para agentes Claude Code neste repo | [`CLAUDE.md`](CLAUDE.md) |

## Architecture

```text
┌─────────────────────────── Snowflake account do CLIENTE ───────────────────────────┐
│                                                                                       │
│   Native App: NEXUS_AI_DATAOPS                                                      │
│   ┌───────────────┐   ┌──────────────────────┐   ┌────────────────────────────┐    │
│   │ Streamlit UI  │──▶│ Cortex Agents (x6)    │──▶│ Cortex Analyst / Search    │    │
│   │ (14 páginas)  │   │ executive · customer  │   │ 5 semantic models          │    │
│   │               │   │ revenue · risk        │   │ 3 search services           │    │
│   │               │   │ data_steward · ops    │   │                             │    │
│   └───────────────┘   └──────────────────────┘   └────────────────────────────┘    │
│           │                                                    │                    │
│           ▼                                                    ▼                    │
│   ┌──────────────────────────── Camada de dados (RBAC + RAP por org_id) ────────┐   │
│   │ CORE (bronze) → MART/AI (silver/gold, Dynamic Tables + dbt) → AUDIT/GOVERN  │   │
│   └──────────────────────────────────────────────────────────────────────────────┘   │
│                                        ▲                                            │
│                            references: (manifest.yml)                              │
└────────────────────────────────────────┼────────────────────────────────────────────┘
                                          │  (tabelas do cliente, sem cópia de dado)
┌─────────────────────────── Infra do PROVIDER (fora do app) ────────────────────────┐
│  Terraform (databases/warehouses/rbac/security/monitoring)                          │
│  Airflow (DAGs de ingestão: Salesforce, Zendesk, Stripe, SAP, Oracle, HubSpot)       │
│  GitHub Actions (lint → test → deploy-dev → native-app-dev → release por tag)       │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

Camadas de dado seguem padrão Medallion: `CORE` (bronze), `MART`/dbt intermediate (silver), `MART`/`AI` (gold) — ver diagrama completo em [`ARCHITECTURE.md`](ARCHITECTURE.md).

## Configuration

Variáveis usadas pelos pipelines de ingestão e pela API standalone (não há `.env.example` no repo — configure manualmente ou via secret manager):

| Variável | Usada por | Propósito |
| -------- | --------- | --------- |
| `NEXUS_ORG_ID` | `snowflake/pipelines/*.py` | Org multi-tenant (default `ORG-DEMO-001`) |
| `DEMO_CUSTOMERS` | `demo_data_generator.py` | Nº de clientes sintéticos |
| `SF_INSTANCE_URL`, `SF_CLIENT_ID`, `SF_CLIENT_SECRET`, `SF_USERNAME`, `SF_PASSWORD`, `SF_SECURITY_TOKEN` | `ingest_salesforce.py` | OAuth2 password flow (Salesforce) |
| `ZENDESK_SUBDOMAIN`, `ZENDESK_EMAIL`, `ZENDESK_TOKEN` | `ingest_zendesk.py` | Auth Zendesk API |
| `STRIPE_SECRET_KEY` | `ingest_stripe.py` | Billing (Stripe) |
| `SNOWFLAKE_CONNECTION_STRING` | `pipelines/kbs/load_kb_*.py` | Conexão Snowflake dos loaders de KB |
| `SNOWFLAKE_ACCOUNT` / `_USER` / `_PASSWORD` | `api/main.py`, CI | Auth Snowflake |
| `NEXUS_API_KEYS` | `api/main.py` | Allowlist de API keys |
| `NEXUS_WEBHOOK_SECRET` | `api/main.py` | Validação de assinatura de webhook |
| `ALLOWED_ORIGINS` | `api/main.py` | CORS |

Credenciais do lado do Airflow (provider) são geridas como **Airflow Variables**, não env vars — ver [`airflow/README.md`](airflow/README.md).

## Development

### Setup

```bash
# dbt
cd dbt && pip install -r requirements.txt && dbt deps

# API standalone (FastAPI)
cd api && pip install -r requirements.txt

# Airflow (DAGs do provider)
cd airflow && pip install -r requirements.txt
```

### Running Tests

```bash
# Lint
ruff check app/streamlit/ snowflake/models/ snowflake/pipelines/ --select E,F,W,I --ignore E501

# Testes Python (gate de cobertura 50% sobre snowflake/models)
pytest tests/python/ -v --cov=snowflake/models --cov-report=term-missing --cov-fail-under=50

# dbt
cd dbt && dbt parse --profiles-dir . --profile nexus_snowflake --target dev --vars '{"org_id": "ORG-TEST-001"}'
cd dbt && dbt test   # requer conexão Snowflake válida

# Terraform
cd terraform/environments/dev && terraform fmt -check && terraform validate
```

CI completo em [`.github/workflows/ci.yml`](.github/workflows/ci.yml) (lint → secret scan → SAST → dbt parse/compile → pytest → deploy-dev → native-app-dev). Terraform, dbt (cron diário) e release do Native App por tag têm workflows dedicados em `.github/workflows/`.

## Known Limitations

- Testes de asserção SQL (`tests/sql/*.sql`) rodam em CI com `continue-on-error: true` — ainda não passam de forma confiável contra Snowflake real (bugs conhecidos em views de `INFORMATION_SCHEMA` e sintaxe de `CALL CORE.ASSERT(...)`).
- Gate de cobertura de testes (50%) cobre apenas `snowflake/models`; `app/streamlit` e `snowflake/pipelines` são informativos, não bloqueantes.
- CI autentica no Snowflake com `ACCOUNTADMIN` + senha (não key-pair) e usa `insecure_mode=true` / `SF_OCSP_FAIL_OPEN=true` para contornar falha de validação de certificado em runners do GitHub — débito técnico documentado inline em `ci.yml`.
- Ingestão externa (Salesforce, Zendesk, Stripe, SAP, Oracle, HubSpot) tem scripts e DAGs Airflow prontos, mas sem trigger automático além de execução manual.
- Suporte a Azure e GCS external stages ainda não implementado (ver [`CLOUD_STRATEGY.md`](CLOUD_STRATEGY.md)).
- `bandit` e `pip-audit` rodam em CI mas não bloqueiam o pipeline (`|| true`).

## Contributing

Projeto interno em desenvolvimento ativo via fluxo Spec-Driven Development (Brainstorm → Define → Design → Build → Ship, ver `.claude/sdd/`). Para novas features, use os comandos `/brainstorm`, `/define`, `/design` e `/build` documentados em [`CLAUDE.md`](CLAUDE.md).
