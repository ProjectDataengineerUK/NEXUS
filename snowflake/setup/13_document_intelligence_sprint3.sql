-- NEXUS AI DataOps — Sprint 3: Document Intelligence
-- Stage para upload, SP de chunking com Snowpark, Cortex Search Service

USE ROLE NEXUS_ADMIN;
USE DATABASE NEXUS_APP;
USE WAREHOUSE NEXUS_COMPUTE_WH;

-- ─────────────────────────────────────────────────────────────────────────────
-- Stage interno para upload de documentos
-- ─────────────────────────────────────────────────────────────────────────────

CREATE STAGE IF NOT EXISTS NEXUS_APP.CORE.DOC_STAGE
    DIRECTORY         = (ENABLE = TRUE)
    ENCRYPTION        = (TYPE = 'SNOWFLAKE_SSE')
    COMMENT           = 'Stage interno para contratos, relatórios e documentos NEXUS';

GRANT READ  ON STAGE NEXUS_APP.CORE.DOC_STAGE TO ROLE NEXUS_DATA_ENGINEER;
GRANT WRITE ON STAGE NEXUS_APP.CORE.DOC_STAGE TO ROLE NEXUS_DATA_ENGINEER;
GRANT READ  ON STAGE NEXUS_APP.CORE.DOC_STAGE TO ROLE NEXUS_ADMIN;
GRANT WRITE ON STAGE NEXUS_APP.CORE.DOC_STAGE TO ROLE NEXUS_ADMIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- Stored Procedure: processar documento → extrair texto → chunks → DOCUMENTS
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE NEXUS_APP.CORE.SP_PROCESS_DOCUMENT(
    p_document_id   VARCHAR,
    p_org_id        VARCHAR,
    p_stage_path    VARCHAR,
    p_document_name VARCHAR,
    p_document_type VARCHAR,
    p_entity_id     VARCHAR,
    p_entity_type   VARCHAR
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python', 'pandas')
HANDLER = 'process_document'
EXECUTE AS CALLER
AS $$
import json
import uuid
from datetime import datetime, timezone

def split_into_chunks(text: str, chunk_size: int = 800, overlap: int = 100) -> list[str]:
    """Divide texto em chunks com overlap para manter contexto."""
    if not text:
        return []
    chunks = []
    start = 0
    while start < len(text):
        end = min(start + chunk_size, len(text))
        # Tenta quebrar em parágrafo/sentença para não cortar palavras
        if end < len(text):
            for sep in ['\n\n', '\n', '. ', ' ']:
                pos = text.rfind(sep, start, end)
                if pos > start + chunk_size // 2:
                    end = pos + len(sep)
                    break
        chunks.append(text[start:end].strip())
        start = end - overlap if end < len(text) else end
    return [c for c in chunks if c]

def process_document(session, p_document_id, p_org_id, p_stage_path,
                     p_document_name, p_document_type, p_entity_id, p_entity_type):
    try:
        # 1. Extrai texto com Cortex PARSE_DOCUMENT
        parse_sql = f"""
            SELECT SNOWFLAKE.CORTEX.PARSE_DOCUMENT(
                '@NEXUS_APP.CORE.DOC_STAGE',
                '{p_stage_path}',
                {{'mode': 'LAYOUT'}}
            ) AS parsed
        """
        result = session.sql(parse_sql).collect()
        parsed = result[0]["PARSED"] if result else None

        if not parsed:
            return "ERROR: PARSE_DOCUMENT retornou vazio"

        parsed_dict = json.loads(parsed) if isinstance(parsed, str) else parsed
        full_text = parsed_dict.get("content", "")
        if not full_text:
            return "ERROR: texto extraído vazio"

        # 2. Gera sumário com Cortex
        safe_summary_text = full_text[:3000].replace("'", "''")
        summary_sql = f"""
            SELECT SNOWFLAKE.CORTEX.COMPLETE(
                'mistral-large2',
                CONCAT(
                    'Resuma em 3 frases o seguinte documento corporativo. ',
                    'Identifique partes, valores e datas críticas se houver:',
                    LEFT('{safe_summary_text}', 3000)
                )
            ) AS summary
        """
        summary_result = session.sql(summary_sql).collect()
        summary = summary_result[0]["SUMMARY"] if summary_result else ""

        # 3. Insere registro em CORE.DOCUMENTS
        safe_document_name = p_document_name.replace("'", "''")
        safe_stage_path = p_stage_path.replace("'", "''")
        safe_extracted_text = full_text.replace("'", "''")[:50000]
        safe_summary = summary.replace("'", "''")
        session.sql(f"""
            MERGE INTO NEXUS_APP.CORE.DOCUMENTS AS tgt
            USING (SELECT
                '{p_document_id}'  AS document_id,
                '{p_org_id}'       AS org_id,
                '{p_entity_id}'    AS entity_id,
                '{p_entity_type}'  AS entity_type,
                '{safe_document_name}' AS document_name,
                '{p_document_type}'AS document_type,
                '{safe_stage_path}' AS stage_path,
                '{safe_extracted_text}' AS extracted_text,
                '{safe_summary}' AS summary,
                'completed'        AS processing_status,
                CURRENT_TIMESTAMP() AS processed_at
            ) AS src ON tgt.document_id = src.document_id
            WHEN MATCHED THEN UPDATE SET
                extracted_text    = src.extracted_text,
                summary           = src.summary,
                processing_status = src.processing_status,
                processed_at      = src.processed_at
            WHEN NOT MATCHED THEN INSERT (
                document_id, org_id, entity_id, entity_type, document_name,
                document_type, stage_path, extracted_text, summary,
                processing_status, processed_at
            ) VALUES (
                src.document_id, src.org_id, src.entity_id, src.entity_type,
                src.document_name, src.document_type, src.stage_path,
                src.extracted_text, src.summary,
                src.processing_status, src.processed_at
            )
        """).collect()

        # 4. Divide em chunks e insere em AI.DOCUMENT_CHUNKS
        chunks = split_into_chunks(full_text, chunk_size=800, overlap=100)

        # Limpa chunks anteriores deste documento
        session.sql(f"""
            DELETE FROM NEXUS_APP.AI.DOCUMENT_CHUNKS
            WHERE document_id = '{p_document_id}'
        """).collect()

        # Insere chunks em batch
        rows = []
        for i, chunk_text in enumerate(chunks):
            rows.append({
                "CHUNK_ID":       str(uuid.uuid4()),
                "ORG_ID":         p_org_id,
                "DOCUMENT_ID":    p_document_id,
                "DOCUMENT_NAME":  p_document_name,
                "DOCUMENT_TYPE":  p_document_type,
                "CHUNK_INDEX":    i,
                "CHUNK_TEXT":     chunk_text,
                "PAGE_NUMBER":    None,
                "SECTION_TITLE":  None,
            })

        if rows:
            import pandas as pd
            df = pd.DataFrame(rows)
            sp_df = session.create_dataframe(df)
            sp_df.write.mode("append").save_as_table("NEXUS_APP.AI.DOCUMENT_CHUNKS")

        return f"OK: {len(chunks)} chunks extraídos de '{p_document_name}'"

    except Exception as e:
        # Marca documento como falha
        session.sql(f"""
            UPDATE NEXUS_APP.CORE.DOCUMENTS
            SET processing_status = 'failed'
            WHERE document_id = '{p_document_id}'
        """).collect()
        return f"ERROR: {str(e)}"
$$;

GRANT USAGE ON PROCEDURE NEXUS_APP.CORE.SP_PROCESS_DOCUMENT(
    VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR
) TO ROLE NEXUS_ADMIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- Cortex Search Service sobre AI.DOCUMENT_CHUNKS
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE CORTEX SEARCH SERVICE NEXUS_APP.AI.DOC_SEARCH
    ON chunk_text
    ATTRIBUTES org_id, document_id, document_name, document_type
    WAREHOUSE = NEXUS_COMPUTE_WH
    TARGET_LAG = '1 hour'
    COMMENT = 'Semantic search sobre chunks de documentos NEXUS — contratos, relatórios, manuais'
AS (
    SELECT
        chunk_id,
        org_id,
        document_id,
        document_name,
        document_type,
        chunk_text,
        chunk_index,
        COALESCE(section_title, '') AS section_title
    FROM NEXUS_APP.AI.DOCUMENT_CHUNKS
);

GRANT USAGE ON CORTEX SEARCH SERVICE NEXUS_APP.AI.DOC_SEARCH TO ROLE NEXUS_ANALYST;
GRANT USAGE ON CORTEX SEARCH SERVICE NEXUS_APP.AI.DOC_SEARCH TO ROLE NEXUS_VIEWER;

-- ─────────────────────────────────────────────────────────────────────────────
-- Dados de demonstração — chunks pré-processados para 2 documentos sample
-- (evita precisar fazer upload real na demo)
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO NEXUS_APP.CORE.DOCUMENTS
    (document_id, org_id, entity_id, entity_type, document_name, document_type,
     stage_path, summary, processing_status, processed_at)
VALUES
    ('DOC-001', 'ORG-DEMO-001', 'CUST-001', 'customer',
     'Acme_Master_Agreement_2023.pdf', 'contract',
     'NEXUS_APP.CORE.DOC_STAGE/acme_master_agreement_2023.pdf',
     'Contrato master entre NEXUS e Acme Corporation válido de Jan/2023 a Dez/2025. Valor total: $1.2M ARR. Inclui cláusula de auto-renovação com 90 dias de antecedência. Penalidade de rescisão: 20% do valor remanescente.',
     'completed', CURRENT_TIMESTAMP()),
    ('DOC-002', 'ORG-DEMO-001', 'CUST-003', 'customer',
     'Quantum_Finance_SLA_Agreement.pdf', 'sla',
     'NEXUS_APP.CORE.DOC_STAGE/quantum_finance_sla.pdf',
     'SLA entre NEXUS e Quantum Finance definindo uptime de 99.9%, tempo de resposta P1 < 4h e P2 < 24h. Créditos de serviço previstos para violações acima de 0.1% de downtime mensal.',
     'completed', CURRENT_TIMESTAMP());

INSERT INTO NEXUS_APP.AI.DOCUMENT_CHUNKS
    (org_id, document_id, document_name, document_type, chunk_index, chunk_text, section_title)
VALUES
    -- DOC-001: Acme Master Agreement
    ('ORG-DEMO-001', 'DOC-001', 'Acme_Master_Agreement_2023.pdf', 'contract', 0,
     'CONTRATO MASTER DE SERVIÇOS — NEXUS AI DataOps e Acme Corporation. Este Contrato Master de Serviços ("Contrato") é celebrado entre NEXUS AI DataOps ("Fornecedor") e Acme Corporation ("Cliente") com vigência a partir de 1º de janeiro de 2023. O Contrato estabelece os termos e condições gerais para fornecimento de software e serviços de inteligência artificial corporativa.',
     'Identificação das Partes'),
    ('ORG-DEMO-001', 'DOC-001', 'Acme_Master_Agreement_2023.pdf', 'contract', 1,
     'ESCOPO DOS SERVIÇOS: O Fornecedor disponibilizará ao Cliente a plataforma NEXUS Intelligence Suite, incluindo módulos de Customer & Revenue Intelligence, AI Agents, Cortex Search e Executive Dashboard. O acesso é concedido para até 250 usuários nomeados. Módulos adicionais podem ser contratados mediante Order Form específico.',
     'Escopo dos Serviços'),
    ('ORG-DEMO-001', 'DOC-001', 'Acme_Master_Agreement_2023.pdf', 'contract', 2,
     'VALOR E PAGAMENTO: O valor anual do contrato é de USD 1.200.000,00 (um milhão e duzentos mil dólares), faturado anualmente com vencimento em 30 dias. Reajuste anual pelo IPCA ou 5%, o que for maior. Multa por atraso de 1% ao mês sobre o valor em aberto.',
     'Condições Financeiras'),
    ('ORG-DEMO-001', 'DOC-001', 'Acme_Master_Agreement_2023.pdf', 'contract', 3,
     'RENOVAÇÃO AUTOMÁTICA: O Contrato se renova automaticamente por períodos iguais de 12 meses, salvo notificação de rescisão por qualquer das partes com 90 (noventa) dias de antecedência do término do período vigente. Rescisão antecipada pelo Cliente implica multa de 20% sobre o valor remanescente do período contratado.',
     'Renovação e Rescisão'),
    ('ORG-DEMO-001', 'DOC-001', 'Acme_Master_Agreement_2023.pdf', 'contract', 4,
     'CONFIDENCIALIDADE E DADOS: Todos os dados do Cliente processados pela plataforma permanecem sob custódia e propriedade exclusiva do Cliente em seu ambiente Snowflake. O Fornecedor não acessa, copia ou transfere dados para fora do ambiente contratado. A solução opera como Snowflake Native App, respeitando todas as políticas de segurança do Cliente.',
     'Proteção de Dados'),

    -- DOC-002: Quantum Finance SLA
    ('ORG-DEMO-001', 'DOC-002', 'Quantum_Finance_SLA_Agreement.pdf', 'sla', 0,
     'ACORDO DE NÍVEL DE SERVIÇO (SLA) — NEXUS AI DataOps e Quantum Finance Ltd. Este SLA complementa o Contrato Master e define os níveis de disponibilidade, suporte e resposta para os serviços contratados. Vigência: 1º de março de 2022 a 28 de fevereiro de 2025.',
     'Objeto do SLA'),
    ('ORG-DEMO-001', 'DOC-002', 'Quantum_Finance_SLA_Agreement.pdf', 'sla', 1,
     'DISPONIBILIDADE: O Fornecedor garante disponibilidade mínima de 99,9% mensal para todos os componentes da plataforma, excluindo janelas de manutenção programada (máximo 4h/mês, notificadas com 48h de antecedência) e eventos de força maior. Downtime medido por monitoramento automatizado com granularidade de 1 minuto.',
     'Disponibilidade'),
    ('ORG-DEMO-001', 'DOC-002', 'Quantum_Finance_SLA_Agreement.pdf', 'sla', 2,
     'TEMPOS DE RESPOSTA: P1 (Sistema indisponível / impacto crítico de negócio): resposta em até 1 hora, resolução em até 4 horas. P2 (Funcionalidade degradada / impacto significativo): resposta em até 4 horas, resolução em até 24 horas. P3 (Impacto menor / workaround disponível): resposta em até 8 horas, resolução em até 5 dias úteis.',
     'Categorias de Incidente'),
    ('ORG-DEMO-001', 'DOC-002', 'Quantum_Finance_SLA_Agreement.pdf', 'sla', 3,
     'CRÉDITOS DE SERVIÇO: Violações de disponibilidade geram créditos automáticos: 99,0%-99,9% = 5% da mensalidade; 95,0%-99,0% = 10%; abaixo de 95% = 25%. Créditos acumulados não podem exceder 30% do valor mensal e devem ser solicitados em até 30 dias após o incidente.',
     'Penalidades e Créditos'),
    ('ORG-DEMO-001', 'DOC-002', 'Quantum_Finance_SLA_Agreement.pdf', 'sla', 4,
     'INTEGRAÇÕES MONITORADAS: A integração Salesforce CRM é classificada como P1 — qualquer falha de sincronização superior a 2 horas aciona o protocolo de incidente crítico. A integração Zendesk é P2. Logs de integração devem ser preservados por 90 dias e disponibilizados ao Cliente mediante solicitação.',
     'Integrações Críticas');
