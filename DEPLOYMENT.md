# NEXUS AI DataOps — Guia de Deploy CI/CD

> ⚠️ Este guia foi escrito quando o deploy Snowflake vivia num workflow separado (`02-deploy-snowflake.yml`). Essa lógica foi desde então incorporada aos jobs `deploy-dev` / `native-app-dev` / `deploy-prod` dentro de `ci.yml`. Estrutura abaixo atualizada — ver `.github/workflows/ci.yml` como fonte de verdade.

## Arquitetura do pipeline

```
GitHub Push/PR
      │
      ├── terraform/**  ──►  01-terraform.yml
      │                         Plan (PR) → Apply dev (merge main)
      │                         Apply prod (git tag v*.*.*)
      │
      ├── push/PR       ──►  ci.yml
      │                         lint-and-test → dbt-compile
      │                         deploy-dev (push main): upload artefatos + roda snowflake/setup/*.sql
      │                         native-app-dev (push main): snow app run --force + grants + upload semantic models
      │                         deploy-prod (workflow_dispatch manual): scripts/deploy_snowflake.sh
      │
      ├── diário 04h    ──►  03-dbt.yml (cron)
      │                         dbt deps → run → test → source freshness
      │
      └── git tag v*.*.* ──► 04-release-native-app.yml
                                Package nova versão → Snowflake Marketplace
```

---

## Passo 1 — Bootstrap GCP (uma vez)

```bash
# Autentique o gcloud CLI
gcloud auth login
gcloud config set project SEU_PROJECT_ID

# Cria bucket GCS + Service Account + Workload Identity para Terraform remote state
export GCP_PROJECT=seu-project-id
export GITHUB_REPO_OWNER=sua-org
export GITHUB_REPO_NAME=nexus
bash scripts/bootstrap_gcp.sh
```

O script imprime os valores de `GCP_WORKLOAD_IDENTITY_PROVIDER` e `GCP_SERVICE_ACCOUNT` ao final — use-os no Passo 3.

---

## Passo 2 — Criar usuário de serviço no Snowflake

```sql
-- Execute como ACCOUNTADMIN
CREATE USER NEXUS_DEPLOY_SVC
  PASSWORD     = 'SenhaForteAqui123!'
  DEFAULT_ROLE = SYSADMIN
  COMMENT      = 'Service user para CI/CD — não usar interativamente';

GRANT ROLE SYSADMIN     TO USER NEXUS_DEPLOY_SVC;
GRANT ROLE ACCOUNTADMIN TO USER NEXUS_DEPLOY_SVC;  -- necessário para Native App

-- Alternativa mais segura: RSA key-pair (recomendado para prod)
-- ALTER USER NEXUS_DEPLOY_SVC SET RSA_PUBLIC_KEY = 'MIIBIjANBg...';
```

---

## Passo 3 — Configurar GitHub Secrets

Acesse: **GitHub repo → Settings → Secrets and variables → Actions**

### Secrets necessários (dev)

| Secret | Valor | Onde usar |
|--------|-------|-----------|
| `SNOWFLAKE_ACCOUNT` | `orgname-accountname` | Terraform + deploy |
| `SNOWFLAKE_USER` | `NEXUS_DEPLOY_SVC` | Terraform + deploy |
| `SNOWFLAKE_PASSWORD` | senha do SVC user | Terraform + deploy |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | saída do `bootstrap_gcp.sh` | Terraform backend GCS |
| `GCP_SERVICE_ACCOUNT` | saída do `bootstrap_gcp.sh` | Terraform backend GCS |

### Variables necessárias (dev)

| Variable | Valor |
|----------|-------|
| `GCP_PROJECT` | ID do projeto GCP |

### Secrets adicionais (prod)

| Secret | Valor |
|--------|-------|
| `SNOWFLAKE_PROD_ACCOUNT` | conta Snowflake de produção |
| `SNOWFLAKE_PROD_USER` | SVC user de prod |
| `SNOWFLAKE_PROD_PASSWORD` | senha de prod |
| `GCP_PROD_WORKLOAD_IDENTITY_PROVIDER` | Workload Identity do projeto GCP de prod |
| `GCP_PROD_SERVICE_ACCOUNT` | Service Account de prod |

---

## Passo 4 — Configurar GitHub Environments

Acesse: **Settings → Environments**

### dev
- Sem regras de proteção (deploy automático no merge para main)

### prod
- ✅ **Required reviewers**: adicionar seu usuário
- ✅ **Wait timer**: 5 minutos
- ✅ **Deployment branches**: apenas `main` e tags `v*.*.*`

---

## Passo 5 — Primeiro deploy

```bash
# 1. Push para uma branch de feature
git checkout -b feat/initial-setup
git add .
git commit -m "feat: initial NEXUS setup"
git push origin feat/initial-setup

# 2. Abrir PR → GitHub Actions roda terraform plan e comenta no PR

# 3. Merge para main →
#    - terraform apply (dev)
#    - deploy artefatos Snowflake
#    - dbt run + test
```

---

## Passo 6 — Release de produção

```bash
# Tag semântica dispara o workflow 04-release-native-app
git tag v1.0.0
git push origin v1.0.0

# O workflow:
# 1. Empacota versão no NEXUS_AI_DATAOPS_PKG
# 2. Instala em debug mode para testar
# 3. Cria GitHub Release com instruções de instalação
# 4. Requer aprovação manual (GitHub Environment: prod)
```

---

## Fluxo de desenvolvimento dia a dia

```bash
# Feature nova
git checkout -b feat/nova-feature
# ... desenvolver ...
git push origin feat/nova-feature
# → PR: terraform plan automático

# Merge: deploy automático para dev
git checkout main && git merge feat/nova-feature
git push origin main

# dbt corre todo dia às 04h UTC automaticamente
# Forçar manualmente via GitHub Actions → 03-dbt → Run workflow

# Release para prod
git tag v1.1.0 && git push --tags
# → Aguardar aprovação no GitHub Environments
```

---

## Estrutura de arquivos CI/CD

```
.github/workflows/
├── 01-terraform.yml          # Plan (PR) + Apply (merge/tag)
├── ci.yml                    # lint-and-test, dbt-compile, deploy-dev,
│                              # native-app-dev, deploy-prod (jobs no mesmo arquivo)
├── 03-dbt.yml                # dbt run + test (daily + manual)
└── 04-release-native-app.yml # Package + release (tags)

terraform/
├── environments/
│   ├── dev/
│   │   ├── main.tf           # módulos dev com sizes XS
│   │   ├── versions.tf       # backend GCS configurado
│   │   └── backend.hcl       # bucket GCS + prefix dev
│   └── prod/
│       ├── main.tf           # módulos prod com sizes S/M
│       ├── versions.tf
│       └── backend.hcl       # bucket GCS + prefix prod
└── modules/
    ├── databases/            # DB + schemas
    ├── warehouses/           # warehouses com auto-suspend
    ├── rbac/                 # roles + grants hierárquicos
    ├── security/             # masking policies + RAP
    ├── monitoring/
    └── app/

scripts/
├── bootstrap_gcp.sh          # cria GCS bucket + SA + Workload Identity (uma vez)
└── deploy_snowflake.sh       # usado pelo job deploy-prod (workflow_dispatch manual)
```

---

## Troubleshooting

### Terraform plan falha com "account not found"
```
SNOWFLAKE_ACCOUNT deve ser no formato: orgname-accountname
# Encontrar: Snowsight → (canto inferior esquerdo) → Account name
```

### dbt falha com "Object does not exist"
```bash
# Garantir que os SQL scripts rodaram antes do dbt
# O job deploy-dev (dentro de ci.yml) deve concluir antes do 03-dbt.yml
```

### Native App falha no install
```sql
-- Verificar versões disponíveis
SHOW VERSIONS IN APPLICATION PACKAGE NEXUS_AI_DATAOPS_PKG;

-- Ver logs de instalação
SHOW APPLICATIONS LIKE 'NEXUS%';
```
