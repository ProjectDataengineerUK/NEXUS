#!/usr/bin/env bash
# Cria infraestrutura GCP necessária para o Terraform remote state
# Executar UMA VEZ antes de usar o CI/CD
# Requer: gcloud CLI autenticado com permissões de admin
set -euo pipefail

PROJECT="${GCP_PROJECT:?Defina GCP_PROJECT}"
BUCKET="nexus-terraform-state"
REGION="us-central1"
SA_NAME="nexus-terraform-sa"
SA_EMAIL="${SA_NAME}@${PROJECT}.iam.gserviceaccount.com"
REPO_OWNER="${GITHUB_REPO_OWNER:?Defina GITHUB_REPO_OWNER (ex: minha-org)}"
REPO_NAME="${GITHUB_REPO_NAME:?Defina GITHUB_REPO_NAME (ex: nexus)}"

echo "==> Habilitando APIs necessárias..."
gcloud services enable \
  storage.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  sts.googleapis.com \
  --project="$PROJECT"

echo "==> Criando bucket GCS para Terraform state..."
gcloud storage buckets create "gs://${BUCKET}" \
  --project="$PROJECT" \
  --location="$REGION" \
  --uniform-bucket-level-access \
  2>/dev/null || echo "  bucket já existe, continuando..."

gcloud storage buckets update "gs://${BUCKET}" \
  --versioning

echo "==> Criando Service Account para Terraform..."
gcloud iam service-accounts create "$SA_NAME" \
  --project="$PROJECT" \
  --display-name="NEXUS Terraform CI/CD" \
  2>/dev/null || echo "  service account já existe, continuando..."

echo "==> Concedendo permissões ao Service Account..."
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/storage.admin"

echo "==> Configurando Workload Identity Federation para GitHub Actions..."
gcloud iam workload-identity-pools create "nexus-github-pool" \
  --project="$PROJECT" \
  --location="global" \
  --display-name="NEXUS GitHub Pool" \
  2>/dev/null || echo "  pool já existe, continuando..."

gcloud iam workload-identity-pools providers create-oidc "nexus-github-provider" \
  --project="$PROJECT" \
  --location="global" \
  --workload-identity-pool="nexus-github-pool" \
  --display-name="GitHub Actions OIDC" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  2>/dev/null || echo "  provider já existe, continuando..."

POOL_ID=$(gcloud iam workload-identity-pools describe "nexus-github-pool" \
  --project="$PROJECT" \
  --location="global" \
  --format="value(name)")

gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
  --project="$PROJECT" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/${POOL_ID}/attribute.repository/${REPO_OWNER}/${REPO_NAME}"

PROVIDER_NAME=$(gcloud iam workload-identity-pools providers describe "nexus-github-provider" \
  --project="$PROJECT" \
  --location="global" \
  --workload-identity-pool="nexus-github-pool" \
  --format="value(name)")

echo ""
echo "Bootstrap concluído!"
echo ""
echo "Adicione estes GitHub Secrets:"
echo "  GCP_WORKLOAD_IDENTITY_PROVIDER = ${PROVIDER_NAME}"
echo "  GCP_SERVICE_ACCOUNT            = ${SA_EMAIL}"
echo ""
echo "Adicione esta GitHub Variable:"
echo "  GCP_PROJECT = ${PROJECT}"
echo ""
echo "Próximo passo: configure os Snowflake Secrets listados em DEPLOYMENT.md"
