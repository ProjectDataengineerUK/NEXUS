-- NEXUS AI DataOps — Network Rules (zero egress policy)
-- Bloqueia todo tráfego de saída exceto integrações aprovadas

USE ROLE ACCOUNTADMIN;
USE DATABASE NEXUS_APP;

-- Regra: bloquear egress por padrão (aplicada via External Access Integration)
-- Em Snowflake, External Access Integrations controlam outbound HTTP.
-- Sem uma EAI habilitada, funções Python não podem fazer chamadas externas.

-- EAI opcional para M7 (Workflow Automation) — desabilitada por padrão
-- Requer aprovação explícita do consumer ao instalar o Native App

CREATE OR REPLACE NETWORK RULE NEXUS_APP.CONFIG.ALLOW_SLACK_RULE
    TYPE = HOST_PORT
    MODE = EGRESS
    VALUE_LIST = ('hooks.slack.com:443', 'slack.com:443')
    COMMENT = 'Slack webhooks para M7 Workflow Automation (opcional)';

CREATE OR REPLACE NETWORK RULE NEXUS_APP.CONFIG.ALLOW_JIRA_RULE
    TYPE = HOST_PORT
    MODE = EGRESS
    VALUE_LIST = ('*.atlassian.net:443')
    COMMENT = 'Jira API para M7 Workflow Automation (opcional)';

CREATE OR REPLACE NETWORK RULE NEXUS_APP.CONFIG.ALLOW_SERVICENOW_RULE
    TYPE = HOST_PORT
    MODE = EGRESS
    VALUE_LIST = ('*.service-now.com:443')
    COMMENT = 'ServiceNow API para M7 Workflow Automation (opcional)';

-- EAI desabilitada por padrão — consumer deve habilitar explicitamente via Admin Console
-- CREATE EXTERNAL ACCESS INTEGRATION NEXUS_WORKFLOW_EAI
--     ALLOWED_NETWORK_RULES = (NEXUS_APP.CONFIG.ALLOW_SLACK_RULE)
--     ENABLED = FALSE;

COMMENT ON DATABASE NEXUS_APP IS 'NEXUS AI DataOps — dados 100% dentro do perímetro Snowflake. External Access Integrations desabilitadas por padrão. Habilitar via Admin Console (M8) apenas se necessário.';
