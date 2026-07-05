-- NEXUS AI DataOps — Sample / Seed Data
-- Demonstração com 1 org_id de referência: 'ORG-DEMO-001'

USE ROLE NEXUS_ADMIN;
USE DATABASE NEXUS_APP;

-- ─────────────────────────────────────────────
-- CORE.CUSTOMERS
-- ─────────────────────────────────────────────
INSERT INTO NEXUS_APP.CORE.CUSTOMERS
    (customer_id, org_id, name, email, segment, region, industry, lifecycle_stage,
     arr, mrr, contract_start_date, contract_end_date, nps_score, source_system)
VALUES
    ('CUST-001', 'ORG-DEMO-001', 'Acme Corporation',       'ops@acme.com',       'ENTERPRISE', 'North America', 'Manufacturing',    'active',  1200000.00, 100000.00, '2023-01-01', '2025-12-31', 72,  'salesforce'),
    ('CUST-002', 'ORG-DEMO-001', 'Bright Retail Co.',      'cto@bright.com',     'MID_MARKET', 'Europe',         'Retail',           'active',   360000.00,  30000.00, '2023-06-15', '2025-06-14', 45,  'salesforce'),
    ('CUST-003', 'ORG-DEMO-001', 'Quantum Finance Ltd.',   'it@quantum.com',     'ENTERPRISE', 'APAC',           'Financial Services','at_risk',  840000.00,  70000.00, '2022-03-01', '2025-02-28', 28,  'salesforce'),
    ('CUST-004', 'ORG-DEMO-001', 'Nova Health Systems',    'data@nova.com',      'MID_MARKET', 'North America',  'Healthcare',       'active',   480000.00,  40000.00, '2024-01-15', '2025-01-14', 68,  'salesforce'),
    ('CUST-005', 'ORG-DEMO-001', 'Stellar SaaS Inc.',      'admin@stellar.io',   'SMB',        'Europe',         'Technology',       'active',    96000.00,   8000.00, '2024-03-01', '2025-02-28', 81,  'salesforce'),
    ('CUST-006', 'ORG-DEMO-001', 'Global Logistics SA',   'ops@global-log.com', 'ENTERPRISE', 'Latin America',  'Logistics',        'churned',  960000.00,  80000.00, '2021-07-01', '2024-06-30', 15,  'salesforce'),
    ('CUST-007', 'ORG-DEMO-001', 'Peak Energy Ltd.',       'cfo@peak.com',       'MID_MARKET', 'North America',  'Energy',           'active',   240000.00,  20000.00, '2023-11-01', '2025-10-31', 55,  'salesforce'),
    ('CUST-008', 'ORG-DEMO-001', 'Apex Telecom',           'it@apex.com',        'ENTERPRISE', 'Europe',         'Telecommunications','at_risk',  720000.00,  60000.00, '2022-09-01', '2025-08-31', 33,  'salesforce'),
    ('CUST-009', 'ORG-DEMO-001', 'FastFood Chain Corp.',   'tech@fastfood.com',  'MID_MARKET', 'North America',  'Food & Beverage',  'active',   300000.00,  25000.00, '2024-02-01', '2026-01-31', 60,  'salesforce'),
    ('CUST-010', 'ORG-DEMO-001', 'Sunrise Pharma',         'data@sunrise.com',   'ENTERPRISE', 'APAC',           'Pharmaceuticals',  'active',  1560000.00, 130000.00, '2023-04-01', '2026-03-31', 77,  'salesforce');

-- ─────────────────────────────────────────────
-- CORE.PRODUCTS
-- ─────────────────────────────────────────────
INSERT INTO NEXUS_APP.CORE.PRODUCTS
    (product_id, org_id, name, category, product_name, product_category, unit_price, currency, is_active)
VALUES
    ('PROD-001', 'ORG-DEMO-001', 'NEXUS Intelligence Suite',    'platform',    'NEXUS Intelligence Suite',    'platform',    120000.00, 'USD', TRUE),
    ('PROD-002', 'ORG-DEMO-001', 'NEXUS Revenue Pack',          'vertical',    'NEXUS Revenue Pack',          'vertical',     36000.00, 'USD', TRUE),
    ('PROD-003', 'ORG-DEMO-001', 'NEXUS Risk & Compliance Pack','vertical',    'NEXUS Risk & Compliance Pack','vertical',     48000.00, 'USD', TRUE),
    ('PROD-004', 'ORG-DEMO-001', 'NEXUS Document Intelligence', 'add-on',      'NEXUS Document Intelligence', 'add-on',       24000.00, 'USD', TRUE),
    ('PROD-005', 'ORG-DEMO-001', 'NEXUS AI Agents (10 seats)',  'add-on',      'NEXUS AI Agents (10 seats)',  'add-on',       60000.00, 'USD', TRUE);

-- ─────────────────────────────────────────────
-- CORE.TRANSACTIONS
-- ─────────────────────────────────────────────
INSERT INTO NEXUS_APP.CORE.TRANSACTIONS
    (transaction_id, org_id, customer_id, product_id, amount, transaction_type, status, transaction_date, source_system)
VALUES
    ('TXN-001', 'ORG-DEMO-001', 'CUST-001', 'PROD-001',  120000.00, 'new_contract',  'completed', '2023-01-01', 'stripe'),
    ('TXN-002', 'ORG-DEMO-001', 'CUST-001', 'PROD-002',   36000.00, 'upsell',        'completed', '2023-06-15', 'stripe'),
    ('TXN-003', 'ORG-DEMO-001', 'CUST-002', 'PROD-001',  120000.00, 'new_contract',  'completed', '2023-06-15', 'stripe'),
    ('TXN-004', 'ORG-DEMO-001', 'CUST-003', 'PROD-001',  120000.00, 'renewal',       'completed', '2024-03-01', 'stripe'),
    ('TXN-005', 'ORG-DEMO-001', 'CUST-003', 'PROD-003',   48000.00, 'new_contract',  'completed', '2023-03-01', 'stripe'),
    ('TXN-006', 'ORG-DEMO-001', 'CUST-004', 'PROD-001',  120000.00, 'new_contract',  'completed', '2024-01-15', 'stripe'),
    ('TXN-007', 'ORG-DEMO-001', 'CUST-005', 'PROD-002',   36000.00, 'new_contract',  'completed', '2024-03-01', 'stripe'),
    ('TXN-008', 'ORG-DEMO-001', 'CUST-006', 'PROD-001',  120000.00, 'new_contract',  'completed', '2021-07-01', 'stripe'),
    ('TXN-009', 'ORG-DEMO-001', 'CUST-007', 'PROD-002',   36000.00, 'new_contract',  'completed', '2023-11-01', 'stripe'),
    ('TXN-010', 'ORG-DEMO-001', 'CUST-008', 'PROD-001',  120000.00, 'renewal',       'completed', '2024-09-01', 'stripe'),
    ('TXN-011', 'ORG-DEMO-001', 'CUST-009', 'PROD-002',   36000.00, 'new_contract',  'completed', '2024-02-01', 'stripe'),
    ('TXN-012', 'ORG-DEMO-001', 'CUST-010', 'PROD-001',  120000.00, 'new_contract',  'completed', '2023-04-01', 'stripe'),
    ('TXN-013', 'ORG-DEMO-001', 'CUST-010', 'PROD-005',   60000.00, 'upsell',        'completed', '2023-10-01', 'stripe');

-- ─────────────────────────────────────────────
-- CORE.TICKETS
-- ─────────────────────────────────────────────
INSERT INTO NEXUS_APP.CORE.TICKETS
    (ticket_id, org_id, customer_id, subject, description, status, priority, sentiment_score, sentiment_label, sla_breach, source_system)
VALUES
    ('TICK-001', 'ORG-DEMO-001', 'CUST-001', 'Dashboard não carrega',          'O painel executivo trava ao abrir.',               'open',     'high',   -0.62, 'negative', FALSE, 'zendesk'),
    ('TICK-002', 'ORG-DEMO-001', 'CUST-001', 'Relatório de NPS incorreto',     'Valores divergem do CRM.',                         'resolved', 'medium',  0.10, 'neutral',  FALSE, 'zendesk'),
    ('TICK-003', 'ORG-DEMO-001', 'CUST-003', 'Integração Salesforce falhou',   'Sync interrompido há 3 dias. Impacto crítico.',     'open',     'urgent', -0.88, 'negative', TRUE,  'zendesk'),
    ('TICK-004', 'ORG-DEMO-001', 'CUST-003', 'Dados de churn errados',         'Probabilidade está sempre 100%.',                  'open',     'high',   -0.71, 'negative', FALSE, 'zendesk'),
    ('TICK-005', 'ORG-DEMO-001', 'CUST-005', 'Excelente onboarding!',          'Equipe adorou o treinamento inicial.',              'closed',   'low',     0.95, 'positive', FALSE, 'zendesk'),
    ('TICK-006', 'ORG-DEMO-001', 'CUST-006', 'Não consigo acessar o sistema',  'Login travado após atualização.',                  'closed',   'urgent', -0.75, 'negative', TRUE,  'zendesk'),
    ('TICK-007', 'ORG-DEMO-001', 'CUST-008', 'Alertas de anomalia excessivos', 'Recebemos 200+ alertas por dia.',                  'open',     'high',   -0.55, 'negative', FALSE, 'zendesk'),
    ('TICK-008', 'ORG-DEMO-001', 'CUST-009', 'Feature request: export PDF',    'Precisamos exportar relatórios para PDF.',         'open',     'low',     0.30, 'neutral',  FALSE, 'zendesk'),
    ('TICK-009', 'ORG-DEMO-001', 'CUST-010', 'Previsão de churn muito precisa','Agora usamos como base para QBR.',                  'closed',   'low',     0.90, 'positive', FALSE, 'zendesk'),
    ('TICK-010', 'ORG-DEMO-001', 'CUST-002', 'Erro ao importar dados históricos','Upload de CSV falha para arquivos > 1GB.',        'open',     'medium', -0.40, 'negative', FALSE, 'zendesk');

-- ─────────────────────────────────────────────
-- CORE.CONTRACTS
-- ─────────────────────────────────────────────
INSERT INTO NEXUS_APP.CORE.CONTRACTS
    (contract_id, org_id, customer_id, contract_name, contract_value, start_date, end_date, auto_renewal, status, source_system)
VALUES
    ('CONT-001', 'ORG-DEMO-001', 'CUST-001', 'Acme Master Agreement 2023',      1200000.00, '2023-01-01', '2025-12-31', TRUE,  'active',  'salesforce'),
    ('CONT-002', 'ORG-DEMO-001', 'CUST-002', 'Bright Retail SaaS Agreement',     360000.00, '2023-06-15', '2025-06-14', FALSE, 'active',  'salesforce'),
    ('CONT-003', 'ORG-DEMO-001', 'CUST-003', 'Quantum Finance Platform License',  840000.00, '2022-03-01', '2025-02-28', FALSE, 'active',  'salesforce'),
    ('CONT-004', 'ORG-DEMO-001', 'CUST-004', 'Nova Health Annual Contract',       480000.00, '2024-01-15', '2025-01-14', TRUE,  'active',  'salesforce'),
    ('CONT-005', 'ORG-DEMO-001', 'CUST-006', 'Global Logistics Enterprise',       960000.00, '2021-07-01', '2024-06-30', FALSE, 'expired', 'salesforce'),
    ('CONT-006', 'ORG-DEMO-001', 'CUST-008', 'Apex Telecom 3-Year Deal',          720000.00, '2022-09-01', '2025-08-31', FALSE, 'active',  'salesforce'),
    ('CONT-007', 'ORG-DEMO-001', 'CUST-010', 'Sunrise Pharma Global Agreement', 1560000.00, '2023-04-01', '2026-03-31', TRUE,  'active',  'salesforce');

-- ─────────────────────────────────────────────
-- AI.CHURN_SCORES
-- ─────────────────────────────────────────────
INSERT INTO NEXUS_APP.AI.CHURN_SCORES
    (org_id, customer_id, churn_probability, risk_level, recommended_action, expected_revenue_at_risk, model_version)
VALUES
    ('ORG-DEMO-001', 'CUST-001', 0.12, 'LOW',    'Schedule QBR before Q4 renewal',           144000.00, 'v1.0'),
    ('ORG-DEMO-001', 'CUST-002', 0.38, 'MEDIUM', 'Address open ticket — CSV import bug',       43200.00, 'v1.0'),
    ('ORG-DEMO-001', 'CUST-003', 0.81, 'HIGH',   'URGENT: Fix Salesforce sync, executive call',840000.00, 'v1.0'),
    ('ORG-DEMO-001', 'CUST-004', 0.09, 'LOW',    'Offer upsell on Document Intelligence',      57600.00, 'v1.0'),
    ('ORG-DEMO-001', 'CUST-005', 0.05, 'LOW',    'Identify expansion opportunity',             11520.00, 'v1.0'),
    ('ORG-DEMO-001', 'CUST-007', 0.42, 'MEDIUM', 'Engage CSM — no activity in 45 days',        28800.00, 'v1.0'),
    ('ORG-DEMO-001', 'CUST-008', 0.73, 'HIGH',   'URGENT: Reduce alert noise, review SLA',    864000.00, 'v1.0'),
    ('ORG-DEMO-001', 'CUST-009', 0.15, 'LOW',    'Expand to Revenue Pack',                     45000.00, 'v1.0'),
    ('ORG-DEMO-001', 'CUST-010', 0.08, 'LOW',    'Prepare 3-year renewal proposal',           624000.00, 'v1.0');

-- ─────────────────────────────────────────────
-- AI.RECOMMENDATIONS
-- ─────────────────────────────────────────────
INSERT INTO NEXUS_APP.AI.RECOMMENDATIONS
    (org_id, entity_id, entity_type, recommendation_type, priority, recommendation_text, expected_impact_usd, confidence_score, owner_role, status)
VALUES
    ('ORG-DEMO-001', 'CUST-003', 'customer', 'churn_prevention', 'HIGH',
     'Quantum Finance está em risco crítico. A integração Salesforce falhou há 3 dias e o NPS caiu para 28. Agende call executiva nas próximas 24h e envolva engenharia para resolver o sync.',
     840000.00, 0.92, 'Customer Success Manager', 'pending'),
    ('ORG-DEMO-001', 'CUST-008', 'customer', 'churn_prevention', 'HIGH',
     'Apex Telecom recebe 200+ alertas/dia — equipe está sobrecarregada. Revise thresholds de anomalia e ofereça sessão de tuning gratuita.',
     864000.00, 0.87, 'Customer Success Manager', 'pending'),
    ('ORG-DEMO-001', 'CUST-004', 'customer', 'upsell', 'MEDIUM',
     'Nova Health processa 500+ documentos/mês manualmente. NEXUS Document Intelligence reduziria 80% do esforço. Impacto estimado: $80k/ano em eficiência.',
      57600.00, 0.78, 'Account Executive', 'pending'),
    ('ORG-DEMO-001', 'CUST-001', 'customer', 'renewal', 'MEDIUM',
     'Acme Corporation renova em Dez/2025. NPS 72 e uso acelerado. Proponha upgrade para 3 anos com desconto de 10% — protege $1.2M ARR.',
     144000.00, 0.83, 'Account Executive', 'pending'),
    ('ORG-DEMO-001', 'CUST-010', 'customer', 'expansion', 'MEDIUM',
     'Sunrise Pharma adotou Churn Prediction como base de QBR. Alta satisfação (NPS 77). Momento ideal para propor o pacote Risk & Compliance para equipe regulatória.',
     187200.00, 0.81, 'Account Executive', 'pending');

-- ─────────────────────────────────────────────
-- CORE.SUBSCRIPTIONS
-- ─────────────────────────────────────────────
INSERT INTO NEXUS_APP.CORE.SUBSCRIPTIONS
    (subscription_id, org_id, customer_id, product_id, plan_name, plan_tier, status,
     seats, mrr, arr, current_period_start, current_period_end, source_system)
VALUES
    ('SUB-001', 'ORG-DEMO-001', 'CUST-001', 'PROD-001', 'NEXUS Intelligence Suite',   'enterprise', 'active',  250, 100000.00, 1200000.00, '2025-01-01', '2025-12-31', 'stripe'),
    ('SUB-002', 'ORG-DEMO-001', 'CUST-001', 'PROD-002', 'NEXUS Revenue Pack',          'enterprise', 'active',  250,   3000.00,   36000.00, '2025-01-01', '2025-12-31', 'stripe'),
    ('SUB-003', 'ORG-DEMO-001', 'CUST-002', 'PROD-001', 'NEXUS Intelligence Suite',   'mid-market', 'active',   80,  30000.00,  360000.00, '2025-06-15', '2026-06-14', 'stripe'),
    ('SUB-004', 'ORG-DEMO-001', 'CUST-003', 'PROD-001', 'NEXUS Intelligence Suite',   'enterprise', 'active',  175,  70000.00,  840000.00, '2025-03-01', '2026-02-28', 'stripe'),
    ('SUB-005', 'ORG-DEMO-001', 'CUST-003', 'PROD-003', 'NEXUS Risk & Compliance Pack','enterprise', 'active',  175,   4000.00,   48000.00, '2025-03-01', '2026-02-28', 'stripe'),
    ('SUB-006', 'ORG-DEMO-001', 'CUST-004', 'PROD-001', 'NEXUS Intelligence Suite',   'mid-market', 'active',  100,  40000.00,  480000.00, '2025-01-15', '2026-01-14', 'stripe'),
    ('SUB-007', 'ORG-DEMO-001', 'CUST-005', 'PROD-002', 'NEXUS Revenue Pack',          'smb',        'active',   20,   8000.00,   96000.00, '2025-03-01', '2026-02-28', 'stripe'),
    ('SUB-008', 'ORG-DEMO-001', 'CUST-007', 'PROD-002', 'NEXUS Revenue Pack',          'mid-market', 'active',   50,  20000.00,  240000.00, '2025-11-01', '2026-10-31', 'stripe'),
    ('SUB-009', 'ORG-DEMO-001', 'CUST-008', 'PROD-001', 'NEXUS Intelligence Suite',   'enterprise', 'active',  150,  60000.00,  720000.00, '2025-09-01', '2026-08-31', 'stripe'),
    ('SUB-010', 'ORG-DEMO-001', 'CUST-009', 'PROD-002', 'NEXUS Revenue Pack',          'mid-market', 'active',   60,  25000.00,  300000.00, '2025-02-01', '2026-01-31', 'stripe'),
    ('SUB-011', 'ORG-DEMO-001', 'CUST-010', 'PROD-001', 'NEXUS Intelligence Suite',   'enterprise', 'active',  300, 130000.00, 1560000.00, '2025-04-01', '2026-03-31', 'stripe'),
    ('SUB-012', 'ORG-DEMO-001', 'CUST-010', 'PROD-005', 'NEXUS AI Agents (10 seats)', 'enterprise', 'active',   10,   5000.00,   60000.00, '2025-10-01', '2026-09-30', 'stripe');

-- ─────────────────────────────────────────────
-- CORE.PRODUCT_EVENTS
-- ─────────────────────────────────────────────
INSERT INTO NEXUS_APP.CORE.PRODUCT_EVENTS
    (org_id, customer_id, subscription_id, event_type, feature_name, event_value, platform, occurred_at)
VALUES
    -- Acme Corporation — uso ativo
    ('ORG-DEMO-001', 'CUST-001', 'SUB-001', 'feature_used',    'executive_dashboard', 1,  'web', DATEADD('day', -1,  CURRENT_TIMESTAMP())),
    ('ORG-DEMO-001', 'CUST-001', 'SUB-001', 'feature_used',    'churn_prediction',    1,  'web', DATEADD('day', -2,  CURRENT_TIMESTAMP())),
    ('ORG-DEMO-001', 'CUST-001', 'SUB-001', 'report_exported', 'pdf_report',          1,  'web', DATEADD('day', -3,  CURRENT_TIMESTAMP())),
    ('ORG-DEMO-001', 'CUST-001', 'SUB-002', 'feature_used',    'revenue_forecast',    1,  'web', DATEADD('day', -1,  CURRENT_TIMESTAMP())),
    -- Quantum Finance — baixo engajamento (risco)
    ('ORG-DEMO-001', 'CUST-003', 'SUB-004', 'login',           NULL,                  1,  'web', DATEADD('day', -14, CURRENT_TIMESTAMP())),
    ('ORG-DEMO-001', 'CUST-003', 'SUB-004', 'login',           NULL,                  1,  'web', DATEADD('day', -30, CURRENT_TIMESTAMP())),
    ('ORG-DEMO-001', 'CUST-003', 'SUB-004', 'sync_failed',     'salesforce_sync',     0,  'api', DATEADD('day', -3,  CURRENT_TIMESTAMP())),
    -- Stellar SaaS — muito ativo
    ('ORG-DEMO-001', 'CUST-005', 'SUB-007', 'feature_used',    'executive_dashboard', 1,  'web', DATEADD('hour', -2, CURRENT_TIMESTAMP())),
    ('ORG-DEMO-001', 'CUST-005', 'SUB-007', 'feature_used',    'ai_chat',             5,  'web', DATEADD('hour', -4, CURRENT_TIMESTAMP())),
    ('ORG-DEMO-001', 'CUST-005', 'SUB-007', 'feature_used',    'customer_360',        3,  'web', DATEADD('day', -1,  CURRENT_TIMESTAMP())),
    -- Apex Telecom — uso problemático
    ('ORG-DEMO-001', 'CUST-008', 'SUB-009', 'alert_triggered', 'anomaly_detection',   200,'api', DATEADD('day', -1,  CURRENT_TIMESTAMP())),
    ('ORG-DEMO-001', 'CUST-008', 'SUB-009', 'alert_triggered', 'anomaly_detection',   180,'api', DATEADD('day', -2,  CURRENT_TIMESTAMP())),
    ('ORG-DEMO-001', 'CUST-008', 'SUB-009', 'feature_used',    'executive_dashboard', 1,  'web', DATEADD('day', -5,  CURRENT_TIMESTAMP())),
    -- Sunrise Pharma — campeão
    ('ORG-DEMO-001', 'CUST-010', 'SUB-011', 'feature_used',    'churn_prediction',    1,  'web', DATEADD('hour', -1, CURRENT_TIMESTAMP())),
    ('ORG-DEMO-001', 'CUST-010', 'SUB-011', 'feature_used',    'executive_dashboard', 1,  'web', DATEADD('hour', -3, CURRENT_TIMESTAMP())),
    ('ORG-DEMO-001', 'CUST-010', 'SUB-012', 'agent_invoked',   'executive_agent',     1,  'web', DATEADD('hour', -2, CURRENT_TIMESTAMP())),
    ('ORG-DEMO-001', 'CUST-010', 'SUB-012', 'agent_invoked',   'revenue_agent',       1,  'web', DATEADD('day', -1,  CURRENT_TIMESTAMP()));
