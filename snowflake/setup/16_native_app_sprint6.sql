-- NEXUS AI DataOps — Sprint 6: Native App Packaging
-- Executa no account do PROVIDER (não do consumer).
-- Referência: https://docs.snowflake.com/en/developer-guide/native-apps/

USE ROLE ACCOUNTADMIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- Application Package (container da Native App no provider)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE APPLICATION PACKAGE IF NOT EXISTS NEXUS_AI_DATAOPS_PKG
    COMMENT = 'NEXUS AI DataOps — Enterprise AI Command Center para Snowflake';

-- Stage dentro do package para os artefatos
CREATE STAGE IF NOT EXISTS NEXUS_AI_DATAOPS_PKG.PUBLIC.APP_STAGE
    DIRECTORY = (ENABLE = TRUE)
    COMMENT   = 'Artefatos do Native App: manifest, setup_script, Streamlit pages';

-- ─────────────────────────────────────────────────────────────────────────────
-- Upload dos artefatos (executar via SnowSQL ou Python SDK)
-- ─────────────────────────────────────────────────────────────────────────────

-- Via SnowSQL CLI:
-- snowsql -c nexus_prod -q "
--   PUT file://snowflake/native_app/manifest.yml
--       @NEXUS_AI_DATAOPS_PKG.PUBLIC.APP_STAGE/v1/
--       OVERWRITE=TRUE AUTO_COMPRESS=FALSE;
--   PUT file://snowflake/native_app/setup_script.sql
--       @NEXUS_AI_DATAOPS_PKG.PUBLIC.APP_STAGE/v1/
--       OVERWRITE=TRUE AUTO_COMPRESS=FALSE;
--   PUT file://app/streamlit/Home.py
--       @NEXUS_AI_DATAOPS_PKG.PUBLIC.APP_STAGE/v1/streamlit/
--       OVERWRITE=TRUE AUTO_COMPRESS=FALSE;
-- " ... (repetir para todas as páginas)

-- Via Snowpark Python SDK (script em tools/upload_native_app.py):
-- session.file.put("snowflake/native_app/manifest.yml",
--     "@NEXUS_AI_DATAOPS_PKG.PUBLIC.APP_STAGE/v1/",
--     overwrite=True, auto_compress=False)

-- ─────────────────────────────────────────────────────────────────────────────
-- Versão 1.0
-- ─────────────────────────────────────────────────────────────────────────────

-- NOTE: Executar os comandos abaixo SOMENTE após upload dos artefatos no APP_STAGE.
-- Execute via SnowSQL ou Snowsight após o pipeline de upload de artefatos (04-release).
--
-- ALTER APPLICATION PACKAGE NEXUS_AI_DATAOPS_PKG
--     ADD VERSION v1_0
--     USING @NEXUS_AI_DATAOPS_PKG.PUBLIC.APP_STAGE/v1/
--     LABEL = '1.0.0 — Customer & Revenue Intelligence';
--
-- ALTER APPLICATION PACKAGE NEXUS_AI_DATAOPS_PKG
--     SET DEFAULT RELEASE DIRECTIVE
--     VERSION = v1_0
--     PATCH = 0;
--
-- CREATE APPLICATION NEXUS_AI_DATAOPS_DEV
--     FROM APPLICATION PACKAGE NEXUS_AI_DATAOPS_PKG
--     USING VERSION v1_0
--     DEBUG_MODE = TRUE
--     COMMENT = 'Instância de desenvolvimento local para testes';
--
-- SHOW SCHEMAS IN DATABASE NEXUS_AI_DATAOPS_DEV;
-- SHOW TABLES   IN DATABASE NEXUS_AI_DATAOPS_DEV;

-- ─────────────────────────────────────────────────────────────────────────────
-- Patch — deploy de atualização sem bump de versão major
-- ─────────────────────────────────────────────────────────────────────────────

-- ALTER APPLICATION PACKAGE NEXUS_AI_DATAOPS_PKG
--     ADD PATCH FOR VERSION v1_0
--     USING @NEXUS_AI_DATAOPS_PKG.PUBLIC.APP_STAGE/v1/;

-- ─────────────────────────────────────────────────────────────────────────────
-- Publicação no Snowflake Marketplace
-- ─────────────────────────────────────────────────────────────────────────────

-- Pré-requisito: conta habilitada como Provider no Marketplace
-- Configurar via Snowsight → Data Products → Provider Studio → New Listing

-- 1. Criar listing:
-- CREATE LISTING NEXUS_AI_DATAOPS_LISTING
--     FOR APPLICATION PACKAGE NEXUS_AI_DATAOPS_PKG
--     AS $$
--     title: "NEXUS AI DataOps"
--     subtitle: "Enterprise AI Command Center for Snowflake"
--     description: "Transform your Snowflake into an intelligent decision system..."
--     categories: ["AI/ML", "Customer Intelligence", "Revenue Intelligence"]
--     pricing: "paid"  -- ou "free_trial"
--     $$;

-- 2. Publicar:
-- ALTER LISTING NEXUS_AI_DATAOPS_LISTING PUBLISH;

-- ─────────────────────────────────────────────────────────────────────────────
-- Verificação do package
-- ─────────────────────────────────────────────────────────────────────────────

SHOW APPLICATION PACKAGES LIKE 'NEXUS_AI_DATAOPS_PKG';
SHOW VERSIONS IN APPLICATION PACKAGE NEXUS_AI_DATAOPS_PKG;
