# NEXUS AI DataOps

> Plataforma horizontal de IA + Dados nativa em Snowflake — um "Enterprise AI Command Center" que transforma o Snowflake de cada cliente em um sistema inteligente de decisão, governança, automação e geração de receita. Distribuído via Snowflake Native App, sem mover dados para fora do ambiente do cliente. Foca em Customer & Revenue Intelligence como ponto de entrada, com expansão para Risk, Supply Chain, Compliance e Operations por packs verticais (financeiro, varejo, saúde, telecom, indústria, hotelaria, SaaS, automotivo).

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
├── CONTEXT.md          ← Conceito completo, roadmap e arquitetura (ChatGPT export)
└── .claude/
    ├── settings.json
    └── hooks/
```

> ⚠️ Projeto em fase de conceito — sem código implementado ainda. A estrutura planejada está documentada em `CONTEXT.md` (seção 20).

## Arquivos-chave

| Arquivo | Função |
|---------|--------|
| `CONTEXT.md` | Conceito completo do produto: ICP, módulos, arquitetura técnica, modelos de dados, roadmap, pricing, GTM e estrutura de código planejada |

## Convenções

- **Linter:** não configurado (projeto sem código ainda)
- **Formatter:** não configurado
- **Testes:** não configurado

## Como rodar

```bash
# Projeto em fase conceitual — sem comandos de execução ainda
# Próximo passo: criar estrutura base do Snowflake Native App
# Ver CONTEXT.md seção 33 para o Sprint 1 sugerido
```

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
