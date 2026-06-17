#!/usr/bin/env bash
# =============================================================================
# NEXUS AI DataOps — Bootstrap Completo
# Executa UMA VEZ para configurar toda a infraestrutura e CI/CD.
#
# Pré-requisitos:
#   gcloud CLI  → autenticado com permissão de admin no projeto GCP
#   gh CLI      → autenticado (gh auth login)
#   python3     → com snowflake-connector-python instalado
#   snowsql     → opcional (usamos python como fallback)
#
# Uso:
#   export GCP_PROJECT="meu-projeto-gcp"
#   export SNOWFLAKE_ACCOUNT="MYORG-AB12345"
#   export SNOWFLAKE_ADMIN_USER="jonatas"          # usuário ACCOUNTADMIN existente
#   export SNOWFLAKE_ADMIN_PASSWORD="senha-atual"  # senha do usuário acima
#   export SNOWFLAKE_DEPLOY_PASSWORD="nova-senha-deploy-123!"
#   ./scripts/bootstrap.sh
#
# Todas as variáveis também podem ser informadas interativamente.
# =============================================================================
set -euo pipefail

# ── Cores ─────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

step()  { echo -e "\n${CYAN}${BOLD}[▶] $*${RESET}"; }
ok()    { echo -e "${GREEN}    ✓ $*${RESET}"; }
warn()  { echo -e "${YELLOW}    ⚠ $*${RESET}"; }
die()   { echo -e "${RED}    ✗ $*${RESET}"; exit 1; }
ask()   { local var="$1" prompt="$2" default="${3:-}"
          if [ -z "${!var:-}" ]; then
            read -rp "  ${prompt}${default:+ [$default]}: " val
            eval "$var=\"${val:-$default}\""
          fi
          [ -n "${!var}" ] || die "$var é obrigatório." ; }
askpw() { local var="$1" prompt="$2"
          if [ -z "${!var:-}" ]; then
            read -rsp "  ${prompt}: " val; echo
            eval "$var=\"$val\""
          fi
          [ -n "${!var}" ] || die "$var é obrigatório."; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Banner ────────────────────────────────────────────────────────────────────
echo -e "${BOLD}"
cat <<'EOF'
╔══════════════════════════════════════════════════════╗
║        NEXUS AI DataOps — Bootstrap Completo        ║
║   GCP · Snowflake · GitHub Secrets · CI/CD Trigger  ║
╚══════════════════════════════════════════════════════╝
EOF
echo -e "${RESET}"

# ── 0. Verificar dependências ─────────────────────────────────────────────────
step "0/6 · Verificando dependências"

for cmd in gcloud gh python3; do
  command -v "$cmd" &>/dev/null && ok "$cmd disponível" \
    || die "$cmd não encontrado. Instale antes de continuar."
done

python3 -c "import snowflake.connector" 2>/dev/null \
  && ok "snowflake-connector-python instalado" \
  || { warn "Instalando snowflake-connector-python..."; pip3 install -q snowflake-connector-python; }

gh auth status &>/dev/null \
  && ok "gh CLI autenticado" \
  || die "Execute 'gh auth login' antes de continuar."

gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q @ \
  && ok "gcloud autenticado" \
  || die "Execute 'gcloud auth login' antes de continuar."

# ── 1. Coletar inputs ─────────────────────────────────────────────────────────
step "1/6 · Configuração"

# Detectar repo a partir do git remote
GITHUB_REMOTE=$(git -C "$ROOT_DIR" remote get-url origin 2>/dev/null || echo "")
if [[ "$GITHUB_REMOTE" =~ github\.com[:/]([^/]+)/([^/.]+) ]]; then
  DETECTED_OWNER="${BASH_REMATCH[1]}"
  DETECTED_REPO="${BASH_REMATCH[2]}"
  GITHUB_REPO_OWNER="${GITHUB_REPO_OWNER:-$DETECTED_OWNER}"
  GITHUB_REPO_NAME="${GITHUB_REPO_NAME:-$DETECTED_REPO}"
fi

ask GCP_PROJECT           "GCP Project ID"
ask GITHUB_REPO_OWNER     "GitHub owner/org" "${DETECTED_OWNER:-}"
ask GITHUB_REPO_NAME      "GitHub repo name" "${DETECTED_REPO:-}"
ask SNOWFLAKE_ACCOUNT     "Snowflake Account (ex: MYORG-AB12345)"
ask SNOWFLAKE_ADMIN_USER  "Snowflake admin user (ACCOUNTADMIN)" "ACCOUNTADMIN"
askpw SNOWFLAKE_ADMIN_PASSWORD "Senha do admin Snowflake"
askpw SNOWFLAKE_DEPLOY_PASSWORD "Nova senha para NEXUS_DEPLOY_USER"

DEPLOY_USER="NEXUS_DEPLOY_USER"
GCS_BUCKET="nexus-terraform-state"
GCP_REGION="us-central1"
SA_NAME="nexus-terraform-sa"
SA_EMAIL="${SA_NAME}@${GCP_PROJECT}.iam.gserviceaccount.com"
FULL_REPO="${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}"

echo ""
echo -e "  ${BOLD}Resumo:${RESET}"
echo    "  GCP Project  : $GCP_PROJECT"
echo    "  GCS Bucket   : $GCS_BUCKET"
echo    "  GitHub Repo  : $FULL_REPO"
echo    "  SF Account   : $SNOWFLAKE_ACCOUNT"
echo    "  SF Deploy User: $DEPLOY_USER"
echo ""
read -rp "  Continuar? [Y/n]: " confirm
[[ "${confirm,,}" =~ ^(y|yes|)$ ]] || { echo "Abortado."; exit 0; }

# ── 2. GCP: bucket + WIF + Service Account ───────────────────────────────────
step "2/6 · Configurando GCP (bucket Terraform state + Workload Identity)"

gcloud config set project "$GCP_PROJECT" -q

echo "  Habilitando APIs GCP..."
gcloud services enable \
  storage.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  sts.googleapis.com \
  --project="$GCP_PROJECT" -q
ok "APIs habilitadas"

# Bucket
gcloud storage buckets describe "gs://${GCS_BUCKET}" &>/dev/null \
  && warn "Bucket gs://${GCS_BUCKET} já existe" \
  || { gcloud storage buckets create "gs://${GCS_BUCKET}" \
         --project="$GCP_PROJECT" --location="$GCP_REGION" \
         --uniform-bucket-level-access -q
       ok "Bucket criado: gs://${GCS_BUCKET}"; }
gcloud storage buckets update "gs://${GCS_BUCKET}" --versioning -q
ok "Versioning habilitado"

# Service Account
gcloud iam service-accounts describe "$SA_EMAIL" --project="$GCP_PROJECT" &>/dev/null \
  && warn "Service account $SA_EMAIL já existe" \
  || { gcloud iam service-accounts create "$SA_NAME" \
         --project="$GCP_PROJECT" --display-name="NEXUS Terraform CI/CD" -q
       ok "Service account criada: $SA_EMAIL"; }

gcloud storage buckets add-iam-policy-binding "gs://${GCS_BUCKET}" \
  --member="serviceAccount:${SA_EMAIL}" --role="roles/storage.objectAdmin" -q
ok "Permissão storage.objectAdmin concedida"

# Workload Identity Pool
gcloud iam workload-identity-pools describe "nexus-github-pool" \
  --project="$GCP_PROJECT" --location=global &>/dev/null \
  && warn "Workload Identity Pool já existe" \
  || { gcloud iam workload-identity-pools create "nexus-github-pool" \
         --project="$GCP_PROJECT" --location=global \
         --display-name="NEXUS GitHub Pool" -q
       ok "WIF Pool criado"; }

gcloud iam workload-identity-pools providers describe "nexus-github-provider" \
  --project="$GCP_PROJECT" --location=global \
  --workload-identity-pool="nexus-github-pool" &>/dev/null \
  && warn "Provider OIDC já existe" \
  || { gcloud iam workload-identity-pools providers create-oidc "nexus-github-provider" \
         --project="$GCP_PROJECT" --location=global \
         --workload-identity-pool="nexus-github-pool" \
         --display-name="GitHub Actions OIDC" \
         --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
         --issuer-uri="https://token.actions.githubusercontent.com" \
         --attribute-condition="assertion.repository=='${FULL_REPO}'" -q
       ok "Provider OIDC criado"; }

POOL_RESOURCE=$(gcloud iam workload-identity-pools describe "nexus-github-pool" \
  --project="$GCP_PROJECT" --location=global --format="value(name)")

PROVIDER_RESOURCE=$(gcloud iam workload-identity-pools providers describe "nexus-github-provider" \
  --project="$GCP_PROJECT" --location=global \
  --workload-identity-pool="nexus-github-pool" --format="value(name)")

gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
  --project="$GCP_PROJECT" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/${POOL_RESOURCE}/attribute.repository/${FULL_REPO}" -q
ok "Binding WIF ↔ SA concluído"

# ── 3. Snowflake: criar usuário de deploy ─────────────────────────────────────
step "3/6 · Criando usuário de deploy no Snowflake"

python3 - <<PYEOF
import snowflake.connector, sys

try:
    conn = snowflake.connector.connect(
        account="${SNOWFLAKE_ACCOUNT}",
        user="${SNOWFLAKE_ADMIN_USER}",
        password="${SNOWFLAKE_ADMIN_PASSWORD}",
        role="ACCOUNTADMIN",
    )
    cs = conn.cursor()

    stmts = [
        """CREATE USER IF NOT EXISTS ${DEPLOY_USER}
             PASSWORD            = '${SNOWFLAKE_DEPLOY_PASSWORD}'
             DEFAULT_ROLE        = SYSADMIN
             DEFAULT_WAREHOUSE   = COMPUTE_WH
             MUST_CHANGE_PASSWORD = FALSE
             COMMENT             = 'Usuário de deploy NEXUS CI/CD'""",
        "GRANT ROLE SYSADMIN     TO USER ${DEPLOY_USER}",
        "GRANT ROLE ACCOUNTADMIN TO USER ${DEPLOY_USER}",
    ]
    for stmt in stmts:
        cs.execute(stmt)

    cs.close()
    conn.close()
    print("  ✓ Usuário ${DEPLOY_USER} criado/verificado")
except Exception as e:
    print(f"  ✗ Erro Snowflake: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

ok "Snowflake deploy user configurado"

# ── 4. GitHub Environments ────────────────────────────────────────────────────
step "4/6 · Configurando GitHub Environments e Secrets"

for env in dev prod; do
  gh api "repos/${FULL_REPO}/environments/${env}" \
    --method PUT \
    --silent \
    --input - <<JSON
{
  "wait_timer": 0,
  "reviewers": [],
  "deployment_branch_policy": null
}
JSON
  ok "Environment '${env}' criado/atualizado"
done

# Proteção manual em prod
gh api "repos/${FULL_REPO}/environments/prod" \
  --method PUT \
  --silent \
  --input - <<JSON
{
  "wait_timer": 0,
  "prevent_self_review": false,
  "deployment_branch_policy": {
    "protected_branches": false,
    "custom_branch_policies": true
  }
}
JSON
ok "Environment 'prod' com branch policy configurado"

# ── 5. GitHub Secrets ─────────────────────────────────────────────────────────
declare -A SECRETS=(
  [SNOWFLAKE_ACCOUNT]="$SNOWFLAKE_ACCOUNT"
  [SNOWFLAKE_USER]="$DEPLOY_USER"
  [SNOWFLAKE_PASSWORD]="$SNOWFLAKE_DEPLOY_PASSWORD"
  [GCP_WORKLOAD_IDENTITY_PROVIDER]="$PROVIDER_RESOURCE"
  [GCP_SERVICE_ACCOUNT]="$SA_EMAIL"
)

for secret_name in "${!SECRETS[@]}"; do
  echo -n "${SECRETS[$secret_name]}" \
    | gh secret set "$secret_name" --repo "$FULL_REPO" --body -
  ok "Secret $secret_name configurado"
done

# GitHub Variables
gh variable set GCP_PROJECT --repo "$FULL_REPO" --body "$GCP_PROJECT"
ok "Variable GCP_PROJECT configurada"

# Prod secrets (mesma conta por enquanto — trocar quando tiver conta separada)
for secret_name in SNOWFLAKE_ACCOUNT SNOWFLAKE_USER SNOWFLAKE_PASSWORD; do
  echo -n "${SECRETS[$secret_name]}" \
    | gh secret set "SNOWFLAKE_PROD_${secret_name#SNOWFLAKE_}" \
        --repo "$FULL_REPO" --body - 2>/dev/null || true
done
ok "Secrets de prod configurados (espelhando dev)"

# GCP prod (mesma conta por ora)
echo -n "$PROVIDER_RESOURCE" \
  | gh secret set GCP_PROD_WORKLOAD_IDENTITY_PROVIDER --repo "$FULL_REPO" --body -
echo -n "$SA_EMAIL" \
  | gh secret set GCP_PROD_SERVICE_ACCOUNT --repo "$FULL_REPO" --body -
ok "Secrets GCP prod configurados"

# ── 6. Disparar o pipeline ────────────────────────────────────────────────────
step "5/6 · Disparando o pipeline de CI/CD"

gh workflow run "01-terraform.yml" --repo "$FULL_REPO" --ref main \
  2>/dev/null && ok "Workflow 01-terraform.yml disparado" \
  || warn "Não foi possível disparar via workflow_dispatch — push em main dispara automaticamente"

# ── Sumário ───────────────────────────────────────────────────────────────────
step "6/6 · Concluído!"

cat <<EOF

${BOLD}╔══════════════════════════════════════════════════════════╗
║                  Bootstrap concluído!                    ║
╚══════════════════════════════════════════════════════════╝${RESET}

${BOLD}GCP:${RESET}
  Bucket state  : gs://${GCS_BUCKET}
  Service Account: ${SA_EMAIL}
  WIF Provider  : ${PROVIDER_RESOURCE}

${BOLD}Snowflake:${RESET}
  Deploy User   : ${DEPLOY_USER}
  Account       : ${SNOWFLAKE_ACCOUNT}

${BOLD}GitHub Secrets configurados:${RESET}
  ✓ SNOWFLAKE_ACCOUNT
  ✓ SNOWFLAKE_USER
  ✓ SNOWFLAKE_PASSWORD
  ✓ GCP_WORKLOAD_IDENTITY_PROVIDER
  ✓ GCP_SERVICE_ACCOUNT
  ✓ GCP_PROJECT (variable)

${BOLD}Acompanhe o pipeline:${RESET}
  https://github.com/${FULL_REPO}/actions

${BOLD}Sequência automática:${RESET}
  01-terraform  → provisionamento Snowflake (DBs, WHs, RBAC)
       ↓
  02-deploy     → upload SQL, Streamlit, YAML configs
       ↓
  03-dbt        → modelos staging → marts

${BOLD}Para subir para prod:${RESET}
  git tag v1.0.0 && git push --tags

EOF
