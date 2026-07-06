# NEXUS AI DataOps — Airflow (provider-side)

DAGs de ingestão executados no ambiente Airflow do **provider**, não no
Native App do cliente. Cada DAG extrai de uma fonte externa e carrega os
dados brutos em `STAGING.<FONTE>_<OBJETO>` no Snowflake.

## Conectores

| DAG | Fonte | Objetos | CDC |
|-----|-------|---------|-----|
| `salesforce_ingest_dag.py` | Salesforce | Account, Contact, Opportunity, Lead | Não (full extraction) |
| `zendesk_ingest_dag.py` | Zendesk | tickets, users, organizations | Não (full extraction) |
| `stripe_ingest_dag.py` | Stripe | customers, subscriptions, invoices, charges | Não (full extraction) |
| `sap_ingest_dag.py` | SAP (OData) | Customers, Invoices, Orders | Sim — Stream+Task no Snowflake |
| `oracle_ingest_dag.py` | Oracle DB | Customers, Orders, Invoices | Sim — Stream+Task no Snowflake |
| `hubspot_ingest_dag.py` | HubSpot | contacts, deals, companies | Sim — Stream+Task no Snowflake |
| `kbs_refresh_dag.py` | Snowflake/Cortex docs | Knowledge Base search | — |

Os 3 conectores do Sprint 4 (SAP/Oracle/HubSpot) só extraem e carregam
`STAGING.*` — o MERGE incremental para `CORE.*` é feito por Tasks no
Snowflake (`setup_script.sql`), não em Python. Ver
`.claude/sdd/features/DESIGN_NEXUS_SPRINT4_CONNECTORS_CDC.md` para o
racional (Dynamic Tables já fazem refresh incremental nativo entre CORE e
MART, então o CDC explícito fica entre STAGING e CORE).

## Credenciais (Airflow Variables)

Nenhuma credencial é gerenciada via Terraform — todas são configuradas
diretamente no Airflow (UI, CLI `airflow variables set`, ou backend de
secrets como AWS Secrets Manager/Hashicorp Vault configurado no
`airflow.cfg` do ambiente do provider).

| Variable | Conector | Descrição |
|----------|----------|-----------|
| `SALESFORCE_CLIENT_ID` / `SALESFORCE_CLIENT_SECRET` / `SALESFORCE_USERNAME` / `SALESFORCE_PASSWORD` / `SALESFORCE_DOMAIN` | Salesforce | OAuth2 password flow |
| `ZENDESK_SUBDOMAIN` / `ZENDESK_EMAIL` / `ZENDESK_API_TOKEN` | Zendesk | API token auth |
| `STRIPE_SECRET_KEY` | Stripe | Secret key da conta Stripe |
| `SAP_ODATA_BASE_URL` / `SAP_USER` / `SAP_PASSWORD` | SAP | Endpoint OData (SAP Gateway) + Basic Auth |
| `ORACLE_DSN` / `ORACLE_USER` / `ORACLE_PASSWORD` | Oracle | DSN no formato `host:port/service_name`, conexão via `oracledb` thin mode (sem Oracle Instant Client) |
| `HUBSPOT_ACCESS_TOKEN` | HubSpot | Private App token (API v3) |
| `NEXUS_DEFAULT_ORG_ID` | Todos | `org_id` do NEXUS atribuído a este ambiente Airflow — usado para popular a coluna `org_id` das tabelas STAGING (as fontes não têm o conceito de org_id do NEXUS nativamente) |

### Pré-requisitos por fonte

- **SAP**: requer SAP Gateway com serviço OData ativado nas entidades `Customers`, `Invoices`, `Orders` (módulos SD/FI). Não usa RFC/BAPI — evita dependência do SAP NW RFC SDK proprietário no worker do Airflow.
- **Oracle**: `oracledb` roda em modo thin (puro Python), sem precisar do Oracle Instant Client instalado no worker.
- **HubSpot**: token de Private App com escopos `crm.objects.contacts.read`, `crm.objects.deals.read`, `crm.objects.companies.read`.

## Conexão Snowflake

Todos os DAGs usam a mesma conexão Airflow `snowflake_nexus`
(`airflow/connections/snowflake_default.json`) — role `NEXUS_SYSADMIN`,
warehouse `NEXUS_INGEST_WH`, database `NEXUS_APP`.
