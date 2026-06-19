# NEXUS AI DataOps — Cloud Strategy

> **Versão:** 1.1.0 · **Atualizado:** 2026-06-19
>
> NEXUS é um **Snowflake Native App**: roda dentro do ambiente Snowflake do cliente, sem mover dados para fora. A camada de cloud é relevante para (a) a infraestrutura do **provider NEXUS** (ingestão de APIs externas) e (b) os **dados do consumer** que residem em S3, Azure Blob ou GCS e precisam chegar ao Snowflake.

---

## Princípio fundamental

```
Consumer (cliente)         ←  NEXUS Native App  →  Provider (NEXUS team)
───────────────────                                  ─────────────────────
Snowflake on AWS           ←  mesmo código        →  AWS ingestion infra
Snowflake on Azure         ←  mesmo código        →  AWS/Azure ingestion
Snowflake on GCP           ←  mesmo código        →  GCS + Cloud Run
```

O consumer **não sabe nem precisa saber** em qual cloud seu Snowflake está provisionado — o Native App funciona identicamente em AWS, Azure e GCP. O provider controla apenas **como dados chegam ao Snowflake**, não onde o Snowflake roda.

---

## Roadmap de cloud (3 fases)

```
Fase 1 — MVP (agora)
  AWS-first + Snowflake on AWS
  └─ ingestion: Lambda, ECS, S3, Airflow/MWAA
  └─ terraform state: GCS (já implementado)

Fase 2 — Enterprise
  Snowflake Native App + backend AWS mínimo
  └─ suporte a consumers Azure e GCP
  └─ External Stages para S3, Azure Blob e GCS

Fase 3 — Escala global
  Multi-cloud Snowflake-native
  └─ consumers em qualquer cloud/região
  └─ Databricks para ML pesado (opcional)
  └─ Snowpark Container Services para workloads intensivos
```

---

## 1. AWS-first (recomendação CONTEXT.md para MVP)

### Por que AWS-first
- Ecossistema de ingestão mais maduro (Lambda, Glue, MWAA)
- Fivetran e Airbyte têm conectores nativos para AWS
- Snowflake on AWS é a combinação mais comum no mercado
- Kubernetes (EKS) + ECS para pipelines containerizados
- AWS Secrets Manager para gestão de credenciais

### Arquitetura AWS de ingestão

```
Fontes externas (Salesforce, Zendesk, Stripe, SAP, Oracle...)
         │
         ▼
┌─────────────────────────────────────────────┐
│  AWS Ingestion Layer                         │
│  ─────────────────────────────────────────  │
│  Lambda          → triggers de ingestão       │
│  ECS / Fargate   → workers de pipeline        │
│  S3 (raw-zone)   → landing zone de arquivos   │
│  Airflow / MWAA  → orquestração de DAGs       │
│  AWS Glue        → ETL gerenciado (opcional)  │
│  Secrets Manager → credenciais de API         │
└───────────────────────┬─────────────────────┘
                        │
              COPY INTO / Snowpipe
              External Stage (s3://)
                        │
                        ▼
┌─────────────────────────────────────────────┐
│  Snowflake (AWS)                             │
│  NEXUS Native App                            │
│  CORE.CUSTOMERS, CORE.TRANSACTIONS...        │
└─────────────────────────────────────────────┘
```

### Status de implementação AWS

| Componente | Status | Arquivo |
|---|---|---|
| Terraform backend (GCS) | ✅ | `scripts/bootstrap.sh`, `terraform/environments/dev/` |
| `ingest_salesforce.py` | ⚠️ parcial | script existe, sem trigger automático Lambda |
| `ingest_zendesk.py` | ⚠️ parcial | script existe, sem trigger automático |
| `ingest_stripe.py` | ⚠️ parcial | script existe, sem trigger automático |
| Lambda functions | ❌ ausente | não implementado |
| ECS task definitions | ❌ ausente | não implementado |
| S3 External Stage no setup_script | ❌ ausente | `09_network_rules.sql` comentado |
| Airflow DAGs | ❌ ausente | zero arquivos DAG |
| AWS Glue jobs | ❌ ausente | não planejado para MVP |
| AWS Secrets Manager | ❌ ausente | pipelines usam `os.getenv()` |

---

## 2. Azure-first (melhor para enterprise Microsoft)

### Quando usar Azure
- Consumer usa Microsoft 365, Teams, SharePoint, Power BI
- Consumidor tem Azure AD / Entra ID como Identity Provider
- Dados residem em Azure Data Lake Storage Gen2 ou Azure SQL
- Regulatório exige dados na Azure (governo, bancos tradicionais, saúde)

### Arquitetura Azure de ingestão

```
Fontes (Dynamics 365, SharePoint, Azure SQL, Blob Storage...)
         │
         ▼
┌─────────────────────────────────────────────┐
│  Azure Ingestion Layer                       │
│  ─────────────────────────────────────────  │
│  Azure Data Factory  → pipelines ETL         │
│  Azure Functions     → triggers de ingestão  │
│  Azure Logic Apps    → automações low-code   │
│  Azure Container Apps → workers              │
│  ADLS Gen2           → landing zone          │
│  Azure Key Vault     → secrets               │
│  Azure OpenAI (opt.) → complementar Cortex   │
└───────────────────────┬─────────────────────┘
                        │
              COPY INTO / Snowpipe
              External Stage (azure://)
              Storage Integration Snowflake
                        │
                        ▼
┌─────────────────────────────────────────────┐
│  Snowflake (Azure)                           │
│  NEXUS Native App                            │
└─────────────────────────────────────────────┘
```

### Conectores Snowflake para Azure

```sql
-- Storage Integration (a criar no setup do provider, não do Native App)
CREATE STORAGE INTEGRATION NEXUS_AZURE_INT
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'AZURE'
  ENABLED = TRUE
  AZURE_TENANT_ID = '<tenant-id>'
  STORAGE_ALLOWED_LOCATIONS = ('azure://nexusdatalake.blob.core.windows.net/raw/');

-- External Stage apontando para ADLS Gen2
CREATE STAGE CORE.AZURE_RAW_STAGE
  STORAGE_INTEGRATION = NEXUS_AZURE_INT
  URL = 'azure://nexusdatalake.blob.core.windows.net/raw/'
  FILE_FORMAT = (TYPE = 'PARQUET');
```

### Status de implementação Azure

| Componente | Status |
|---|---|
| Azure Data Factory pipelines | ❌ ausente |
| Azure Functions triggers | ❌ ausente |
| External Stage (azure://) | ❌ ausente do setup_script |
| Storage Integration Azure | ❌ ausente |
| Azure AD SSO | ❌ ausente |
| Key Vault para secrets | ❌ ausente |

---

## 3. GCP (Terraform backend + futuro)

### O que já está no GCP hoje

| Componente | Status | Arquivo |
|---|---|---|
| GCS bucket para Terraform state | ✅ **implementado** | `scripts/bootstrap.sh` |
| GCP Workload Identity (OIDC para GitHub Actions) | ✅ **implementado** | `terraform/environments/dev/versions.tf` |
| GCP Service Account para Terraform | ✅ **implementado** | `scripts/bootstrap.sh` |
| Cloud Run para workers (futura) | ❌ ausente | planejado Fase 3 |
| GCS External Stage no Snowflake | ❌ ausente | não implementado |

### Conectores Snowflake para GCS

```sql
-- Storage Integration (a criar fora do Native App)
CREATE STORAGE INTEGRATION NEXUS_GCS_INT
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'GCS'
  ENABLED = TRUE
  STORAGE_ALLOWED_LOCATIONS = ('gcs://nexus-raw-landing/');

-- External Stage
CREATE STAGE CORE.GCS_RAW_STAGE
  STORAGE_INTEGRATION = NEXUS_GCS_INT
  URL = 'gcs://nexus-raw-landing/'
  FILE_FORMAT = (TYPE = 'PARQUET');
```

---

## 4. Databricks (complemento para ML pesado)

Não faz parte do MVP. Entra em Fase 3 para:

| Caso de uso | Quando usar Databricks |
|---|---|
| Feature engineering massivo (>1B linhas) | ✅ Databricks > Snowpark |
| ML customizado / deep learning | ✅ Databricks + MLflow |
| Processamento de IoT em tempo real | ✅ Databricks Spark Streaming |
| Data lake com Delta Lake como formato primário | ✅ Databricks |
| Notebooks colaborativos de data science | ✅ Databricks |
| SQL analytics + BI + governança enterprise | Snowflake |
| Produto empacotado no Marketplace | Snowflake |

### Integração planejada Snowflake ↔ Databricks

```
Databricks (ML pesado)
    │
    │  Delta Sharing / Iceberg / COPY INTO
    ▼
Snowflake (NEXUS)
    │
    ▼
AI.FEATURE_STORE (features prontas)
    │
    ▼
Snowpark ML (inferência leve)
```

---

## 5. Conectores de dados por cloud

### Dados que o cliente precisa conectar (Seção 21 CONTEXT.md)

| Categoria | Fontes | Cloud de origem | Método |
|---|---|---|---|
| CRM | Salesforce, HubSpot | Qualquer | Fivetran / ingest_salesforce.py |
| Suporte | Zendesk, ServiceNow, Freshdesk | Qualquer | Fivetran / ingest_zendesk.py |
| Faturamento | Stripe, Braintree, Adyen | Qualquer | ingest_stripe.py |
| ERP | SAP, Oracle Fusion, NetSuite | On-prem / AWS | JDBC + Glue / Fivetran |
| Data Lake | S3 buckets | AWS | External Stage (s3://) |
| Data Lake | Azure Blob / ADLS Gen2 | Azure | External Stage (azure://) |
| Data Lake | GCS buckets | GCP | External Stage (gcs://) |
| Streaming | Kafka, Kinesis, EventHub | AWS/Azure | Snowpipe Streaming SDK |
| Analytics | Google Analytics, Adobe | Qualquer | Fivetran / API pull |
| HRIS | Workday, BambooHR | Qualquer | Fivetran |
| Comunicação | Slack, Teams | Qualquer | MCP connector |
| Projeto | Jira, Linear, Asana | Qualquer | MCP connector |

### O que está implementado vs planejado

| Conector | Implementado | Trigger automático |
|---|---|---|
| Salesforce → Snowflake | ⚠️ script existe | ❌ sem Lambda/Task |
| Zendesk → Snowflake | ⚠️ script existe | ❌ sem Lambda/Task |
| Stripe → Snowflake | ⚠️ script existe | ❌ sem Lambda/Task |
| S3 External Stage | ❌ | — |
| Azure Blob External Stage | ❌ | — |
| GCS External Stage | ❌ | — |
| Fivetran (managed connectors) | ❌ | — |
| Airbyte (open source) | ❌ | — |
| Snowpipe Streaming SDK | ❌ | — |
| Kafka Connect for Snowflake | ❌ | — |

---

## 6. Manifest.yml — Suporte a consumer data sources

**Gap crítico P0:** o `manifest.yml` atual não tem bloco `references:`, o que impede o consumer de mapear suas tabelas externas durante a instalação pelo Marketplace.

### Como deve ser (a implementar):

```yaml
# snowflake/native_app/manifest.yml (seção a adicionar)
references:
  - name: customer_table
    label: "Tabela de Clientes (CRM)"
    description: "Mapeie sua tabela de clientes — deve ter: customer_id, name, email, created_at"
    object_type: TABLE
    register_callback: CORE.REGISTER_REFERENCE
    required: false

  - name: transactions_table
    label: "Tabela de Transações"
    description: "Mapeie sua tabela de transações — deve ter: transaction_id, customer_id, amount, created_at"
    object_type: TABLE
    register_callback: CORE.REGISTER_REFERENCE
    required: false

  - name: events_table
    label: "Tabela de Eventos de Produto"
    description: "Eventos de uso do produto — deve ter: user_id, event_name, occurred_at"
    object_type: TABLE
    register_callback: CORE.REGISTER_REFERENCE
    required: false
```

---

## 7. Posicionamento de vendas por cloud

| Objeção do cliente | Resposta |
|---|---|
| "Uso Azure, não AWS" | App é Snowflake-native — funciona igual em Azure |
| "Nossos dados estão no S3" | Configuramos External Stage S3 → Snowflake |
| "Usamos Databricks" | Databricks integra com Snowflake via Delta Sharing |
| "Temos dados no GCS" | Configuramos External Stage GCS → Snowflake |
| "Precisamos manter dados na Europa" | Snowflake EU region — NEXUS funciona na mesma region |
| "Somos uma empresa Salesforce" | ingest_salesforce.py + Fivetran connector disponível |

---

## 8. Próximas implementações (P0 → P1)

### P0 — Para primeira demo real
1. Ativar `External Access Integration` (`09_network_rules.sql`)
2. Adicionar `references:` ao `manifest.yml`
3. Criar página Streamlit de onboarding de fontes

### P1 — Para SaaS robusto
4. Criar External Stages (S3, Azure Blob, GCS) configuráveis pelo consumer
5. Implementar Snowflake Tasks para rodar `ingest_*.py` automaticamente
6. Adicionar Airflow DAGs para orquestração dos 3 conectores existentes
7. Documentar processo de configuração de Fivetran → Snowflake
8. Usar Snowflake Secrets Manager (em vez de `os.getenv()`)

---

*Documentação baseada no CONTEXT.md seções 7, 19, 21, 33-38 e auditoria de 4 agentes em 2026-06-19.*
