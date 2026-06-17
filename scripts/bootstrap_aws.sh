#!/usr/bin/env bash
# Cria infraestrutura AWS necessária para o Terraform remote state
# Executar UMA VEZ antes de usar o CI/CD
# Requer: aws CLI configurado com permissões de admin
set -euo pipefail

BUCKET="nexus-terraform-state"
TABLE="nexus-terraform-lock"
REGION="us-east-1"

echo "==> Criando bucket S3 para Terraform state..."
aws s3api create-bucket \
  --bucket "$BUCKET" \
  --region "$REGION" \
  --create-bucket-configuration LocationConstraint="$REGION" \
  2>/dev/null || echo "  bucket já existe, continuando..."

aws s3api put-bucket-versioning \
  --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket "$BUCKET" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}
    }]
  }'

aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo "==> Criando tabela DynamoDB para state locking..."
aws dynamodb create-table \
  --table-name "$TABLE" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$REGION" \
  2>/dev/null || echo "  tabela já existe, continuando..."

echo ""
echo "Bootstrap concluído!"
echo "  S3 bucket:     s3://$BUCKET"
echo "  DynamoDB table: $TABLE"
echo "  Region:         $REGION"
echo ""
echo "Próximo passo: configure os GitHub Secrets listados em DEPLOYMENT.md"
