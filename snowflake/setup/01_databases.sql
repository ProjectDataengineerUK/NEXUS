-- NEXUS AI DataOps — Database & Schema Setup
-- Executar como SYSADMIN ou ACCOUNTADMIN

USE ROLE SYSADMIN;

CREATE DATABASE IF NOT EXISTS NEXUS_APP
    DATA_RETENTION_TIME_IN_DAYS = 7
    COMMENT = 'NEXUS AI DataOps — consumer database';

CREATE DATABASE IF NOT EXISTS NEXUS_PROVIDER
    DATA_RETENTION_TIME_IN_DAYS = 7
    COMMENT = 'NEXUS AI DataOps — provider/package database';

USE DATABASE NEXUS_APP;

CREATE SCHEMA IF NOT EXISTS NEXUS_APP.CORE
    DATA_RETENTION_TIME_IN_DAYS = 7
    COMMENT = 'Entidades consolidadas: Customer, Product, Transaction, Document';

CREATE SCHEMA IF NOT EXISTS NEXUS_APP.RAW
    DATA_RETENTION_TIME_IN_DAYS = 3
    COMMENT = 'Dados brutos imutáveis de fontes externas';

CREATE SCHEMA IF NOT EXISTS NEXUS_APP.STD
    DATA_RETENTION_TIME_IN_DAYS = 7
    COMMENT = 'Dados padronizados — outputs do dbt staging';

CREATE SCHEMA IF NOT EXISTS NEXUS_APP.MART
    DATA_RETENTION_TIME_IN_DAYS = 7
    COMMENT = 'Marts de negócio — outputs do dbt mart models + Dynamic Tables';

CREATE SCHEMA IF NOT EXISTS NEXUS_APP.AI
    DATA_RETENTION_TIME_IN_DAYS = 30
    COMMENT = 'Outputs de IA: scores, embeddings, recomendações, sessões de agente';

CREATE SCHEMA IF NOT EXISTS NEXUS_APP.AUDIT
    DATA_RETENTION_TIME_IN_DAYS = 365
    COMMENT = 'Logs de auditoria: prompts, acessos, ações, qualidade de dados';

CREATE SCHEMA IF NOT EXISTS NEXUS_APP.GOVERNANCE
    DATA_RETENTION_TIME_IN_DAYS = 90
    COMMENT = 'Resultados de Data Metric Functions e políticas de governança';

CREATE SCHEMA IF NOT EXISTS NEXUS_APP.CONFIG
    DATA_RETENTION_TIME_IN_DAYS = 90
    COMMENT = 'Configurações do app: vertical pack, roles, thresholds, ingest log';
