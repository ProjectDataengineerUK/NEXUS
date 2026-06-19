-- NEXUS AI DataOps — External Stages para S3, Azure Blob e GCS
-- Sprint 2 — P1: executar com ACCOUNTADMIN ou role com CREATE INTEGRATION privilege
-- Executar FORA do Native App (no contexto do provider ou consumer com permissão)

-- ─────────────────────────────────────────────────────────────────────────────
-- AWS S3 — Storage Integration + External Stage
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. Criar Storage Integration (provider executa uma vez por consumer)
-- CREATE STORAGE INTEGRATION NEXUS_S3_INT
--     TYPE                      = EXTERNAL_STAGE
--     STORAGE_PROVIDER          = 'S3'
--     ENABLED                   = TRUE
--     STORAGE_ALLOWED_LOCATIONS = ('s3://<consumer-bucket>/nexus-landing/')
--     COMMENT = 'Integração S3 para ingestão de dados do consumer via NEXUS';
--
-- DESC INTEGRATION NEXUS_S3_INT;
-- → Capturar STORAGE_AWS_ROLE_ARN e STORAGE_AWS_EXTERNAL_ID
-- → Criar role na conta AWS do consumer com trust relationship para esse ARN

-- 2. Criar External Stage no Snowflake do consumer
-- CREATE OR REPLACE STAGE CORE.S3_RAW_STAGE
--     STORAGE_INTEGRATION = NEXUS_S3_INT
--     URL                 = 's3://<consumer-bucket>/nexus-landing/'
--     FILE_FORMAT         = (TYPE = 'PARQUET')
--     COMMENT             = 'Stage S3 para dados brutos do consumer';

-- ─────────────────────────────────────────────────────────────────────────────
-- Azure Blob / ADLS Gen2 — Storage Integration + External Stage
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. Criar Storage Integration
-- CREATE STORAGE INTEGRATION NEXUS_AZURE_INT
--     TYPE                      = EXTERNAL_STAGE
--     STORAGE_PROVIDER          = 'AZURE'
--     ENABLED                   = TRUE
--     AZURE_TENANT_ID           = '<consumer-tenant-id>'
--     STORAGE_ALLOWED_LOCATIONS = ('azure://<consumer-account>.blob.core.windows.net/nexus-landing/')
--     COMMENT = 'Integração Azure Blob para ingestão via NEXUS';
--
-- DESC INTEGRATION NEXUS_AZURE_INT;
-- → Capturar AZURE_CONSENT_URL e visitar para autorizar Service Principal
-- → O consumer deve visitar a URL e conceder consentimento

-- 2. Criar External Stage
-- CREATE OR REPLACE STAGE CORE.AZURE_RAW_STAGE
--     STORAGE_INTEGRATION = NEXUS_AZURE_INT
--     URL                 = 'azure://<consumer-account>.blob.core.windows.net/nexus-landing/'
--     FILE_FORMAT         = (TYPE = 'PARQUET')
--     COMMENT             = 'Stage Azure Blob para dados brutos do consumer';

-- ─────────────────────────────────────────────────────────────────────────────
-- GCS — Storage Integration + External Stage
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. Criar Storage Integration
-- CREATE STORAGE INTEGRATION NEXUS_GCS_INT
--     TYPE                      = EXTERNAL_STAGE
--     STORAGE_PROVIDER          = 'GCS'
--     ENABLED                   = TRUE
--     STORAGE_ALLOWED_LOCATIONS = ('gcs://<consumer-bucket>/nexus-landing/')
--     COMMENT = 'Integração GCS para ingestão via NEXUS';
--
-- DESC INTEGRATION NEXUS_GCS_INT;
-- → Capturar STORAGE_GCP_SERVICE_ACCOUNT e dar Storage Object Viewer no bucket GCS

-- 2. Criar External Stage
-- CREATE OR REPLACE STAGE CORE.GCS_RAW_STAGE
--     STORAGE_INTEGRATION = NEXUS_GCS_INT
--     URL                 = 'gcs://<consumer-bucket>/nexus-landing/'
--     FILE_FORMAT         = (TYPE = 'PARQUET')
--     COMMENT             = 'Stage GCS para dados brutos do consumer';

-- ─────────────────────────────────────────────────────────────────────────────
-- COPY INTO automático via Snowpipe (ativar após stage criado)
-- ─────────────────────────────────────────────────────────────────────────────

-- Para S3 (criar Snowpipe após criar S3_RAW_STAGE):
-- CREATE OR REPLACE PIPE CORE.CUSTOMERS_PIPE
--     AUTO_INGEST = TRUE
--     COMMENT     = 'Ingere arquivos de clientes do S3 automaticamente'
-- AS
-- COPY INTO CORE.CUSTOMERS (customer_id, org_id, name, email, created_at)
-- FROM (
--     SELECT $1:customer_id::VARCHAR,
--            $1:org_id::VARCHAR,
--            $1:name::VARCHAR,
--            $1:email::VARCHAR,
--            $1:created_at::TIMESTAMP_TZ
--     FROM @CORE.S3_RAW_STAGE/customers/
-- )
-- FILE_FORMAT = (TYPE = 'PARQUET');
--
-- DESC PIPE CORE.CUSTOMERS_PIPE;
-- → Capturar notification_channel ARN e configurar SQS notification no bucket S3

-- ─────────────────────────────────────────────────────────────────────────────
-- Configuracao via 0_Setup.py (onboarding wizard)
-- ─────────────────────────────────────────────────────────────────────────────
-- O wizard em 0_Setup.py guia o consumer a:
-- 1. Informar qual cloud (AWS/Azure/GCS)
-- 2. Informar bucket/container URL
-- 3. Executar os comandos acima (copiados para o consumer executar como ACCOUNTADMIN)
-- 4. Confirmar que o stage foi criado
-- ─────────────────────────────────────────────────────────────────────────────

-- Placeholder: CONFIG para rastrear qual cloud e stage estão configurados
MERGE INTO CONFIG.APP_SETTINGS t
USING (
    SELECT 'external_stage_cloud' AS setting_key, 'none' AS setting_value, 'Cloud do external stage (s3|azure|gcs|none)' AS description UNION ALL
    SELECT 'external_stage_url',   'none', 'URL do external stage configurado pelo consumer' UNION ALL
    SELECT 'snowpipe_enabled',     'false', 'Snowpipe AUTO_INGEST ativo'
) s ON t.setting_key = s.setting_key
WHEN NOT MATCHED THEN INSERT (setting_key, setting_value, description) VALUES (s.setting_key, s.setting_value, s.description);
