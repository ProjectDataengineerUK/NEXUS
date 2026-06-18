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
-- Coluna extracted_fields em CORE.DOCUMENTS (se ainda não existir)
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE NEXUS_APP.CORE.DOCUMENTS ADD COLUMN IF NOT EXISTS extracted_fields VARIANT;

-- ─────────────────────────────────────────────────────────────────────────────
-- SP principal de enriquecimento Cortex AI por documento
-- Executa: CLASSIFY_TEXT → SUMMARIZE → COMPLETE (extração estruturada)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE NEXUS_APP.AI.SP_PROCESS_DOCUMENT(
    p_document_id   VARCHAR,
    p_org_id        VARCHAR
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'process_document'
EXECUTE AS CALLER
AS $$
import json

# Tipos de documento que recebem extração estruturada de campos
EXTRACTABLE_TYPES = {'contract', 'sla', 'amendment'}

# Labels aceitos pela classificação
CLASSIFICATION_LABELS = [
    'contract', 'sla', 'amendment', 'invoice', 'proposal', 'nda', 'other'
]

EXTRACTION_PROMPT_TEMPLATE = """Você é um especialista em análise de contratos corporativos.
Analise o documento abaixo e extraia as informações no formato JSON especificado.
Responda APENAS com o JSON, sem texto adicional, sem markdown, sem blocos de código.

Formato exigido:
{{
  "effective_date": "YYYY-MM-DD ou null",
  "expiration_date": "YYYY-MM-DD ou null",
  "total_value": "valor numérico como string ou null",
  "total_value_currency": "USD/BRL/EUR ou null",
  "penalty_clause": "descrição resumida ou null",
  "auto_renewal": true/false/null,
  "auto_renewal_notice_days": número ou null,
  "governing_law": "jurisdição/país ou null",
  "parties": ["lista de partes envolvidas"],
  "payment_terms": "descrição ou null",
  "sla_uptime_pct": número ou null,
  "p1_response_hours": número ou null,
  "p1_resolution_hours": número ou null
}}

DOCUMENTO:
{text}"""


def _safe_str(value, max_len: int = 100000) -> str:
    """Trunca e escapa aspas simples para interpolação SQL segura."""
    if value is None:
        return ''
    return str(value)[:max_len].replace("'", "''")


def process_document(session, p_document_id: str, p_org_id: str) -> str:
    try:
        # ── 0. Carrega metadados e texto do documento ──────────────────────────
        meta_rows = session.sql(f"""
            SELECT document_id, document_type, extracted_text
            FROM NEXUS_APP.CORE.DOCUMENTS
            WHERE document_id = '{p_document_id}'
              AND org_id = '{p_org_id}'
            LIMIT 1
        """).collect()

        if not meta_rows:
            return f"ERROR: document_id '{p_document_id}' not found for org '{p_org_id}'"

        meta = meta_rows[0]
        existing_type = (meta['DOCUMENT_TYPE'] or '').lower()
        raw_text = meta['EXTRACTED_TEXT'] or ''

        # Se não há texto extraído, tenta montar a partir dos chunks
        if not raw_text:
            chunk_rows = session.sql(f"""
                SELECT chunk_text
                FROM NEXUS_APP.AI.DOCUMENT_CHUNKS
                WHERE document_id = '{p_document_id}'
                ORDER BY chunk_index
            """).collect()
            raw_text = ' '.join(r['CHUNK_TEXT'] for r in chunk_rows if r['CHUNK_TEXT'])

        if not raw_text:
            return f"ERROR: no text available for document '{p_document_id}'"

        steps_done = []

        # ── 1. CLASSIFY_TEXT ──────────────────────────────────────────────────
        classify_text = _safe_str(raw_text, 2000)
        labels_sql = "ARRAY_CONSTRUCT(" + ", ".join(f"'{l}'" for l in CLASSIFICATION_LABELS) + ")"

        classify_rows = session.sql(f"""
            SELECT SNOWFLAKE.CORTEX.CLASSIFY_TEXT(
                '{classify_text}',
                {labels_sql}
            ) AS result
        """).collect()

        classified_label = existing_type  # fallback
        classified_score = 0.0

        if classify_rows and classify_rows[0]['RESULT'] is not None:
            raw_result = classify_rows[0]['RESULT']
            result_dict = json.loads(raw_result) if isinstance(raw_result, str) else raw_result
            classified_label = (result_dict.get('label') or existing_type).lower()
            classified_score = float(result_dict.get('score') or 0.0)

        steps_done.append(f"classify={classified_label}({classified_score:.2f})")

        # ── 2. SUMMARIZE ──────────────────────────────────────────────────────
        # CORTEX.SUMMARIZE aceita até ~100K chars; usa texto completo truncado
        summarize_text = _safe_str(raw_text, 80000)
        summarize_rows = session.sql(f"""
            SELECT SNOWFLAKE.CORTEX.SUMMARIZE('{summarize_text}') AS summary
        """).collect()

        ai_summary = ''
        if summarize_rows and summarize_rows[0]['SUMMARY']:
            ai_summary = summarize_rows[0]['SUMMARY']

        steps_done.append('summarize=ok' if ai_summary else 'summarize=empty')

        # ── 3. COMPLETE — extração estruturada (apenas contract/sla/amendment) ─
        extracted_fields_json = None
        effective_doc_type = classified_label if classified_score >= 0.6 else existing_type

        if effective_doc_type in EXTRACTABLE_TYPES:
            extract_text = _safe_str(raw_text, 12000)
            prompt = _safe_str(
                EXTRACTION_PROMPT_TEMPLATE.format(text=raw_text[:12000]),
                20000
            )
            complete_rows = session.sql(f"""
                SELECT SNOWFLAKE.CORTEX.COMPLETE('mistral-large2', '{prompt}') AS raw_json
            """).collect()

            if complete_rows and complete_rows[0]['RAW_JSON']:
                raw_json_str = complete_rows[0]['RAW_JSON'].strip()
                # Remove possíveis blocos markdown do modelo
                if raw_json_str.startswith('```'):
                    lines = raw_json_str.splitlines()
                    raw_json_str = '\n'.join(
                        l for l in lines
                        if not l.startswith('```')
                    ).strip()

                # Valida e persiste via TRY_PARSE_JSON para garantir VARIANT válido
                safe_json_str = raw_json_str.replace("'", "''")
                parse_check = session.sql(f"""
                    SELECT TRY_PARSE_JSON('{safe_json_str}') AS parsed
                """).collect()

                if parse_check and parse_check[0]['PARSED'] is not None:
                    extracted_fields_json = safe_json_str
                    steps_done.append('extract=ok')
                else:
                    steps_done.append('extract=parse_failed')
            else:
                steps_done.append('extract=no_response')
        else:
            steps_done.append(f'extract=skipped(type={effective_doc_type})')

        # ── 4. Persiste todos os campos enriquecidos ──────────────────────────
        safe_summary = _safe_str(ai_summary)
        safe_label   = classified_label.replace("'", "''")

        # Monta SET de extracted_fields condicionalmente
        extracted_fields_set = (
            f"extracted_fields = TRY_PARSE_JSON('{extracted_fields_json}'),"
            if extracted_fields_json is not None
            else ""
        )

        # Atualiza document_type apenas se score de confiança >= 0.6
        doc_type_set = (
            f"document_type = '{safe_label}',"
            if classified_score >= 0.6
            else ""
        )

        session.sql(f"""
            UPDATE NEXUS_APP.CORE.DOCUMENTS
            SET
                {doc_type_set}
                document_category = '{safe_label}',
                summary           = '{safe_summary}',
                {extracted_fields_set}
                processing_status = 'completed',
                processed_at      = CURRENT_TIMESTAMP()
            WHERE document_id = '{p_document_id}'
              AND org_id = '{p_org_id}'
        """).collect()

        return "OK: " + " | ".join(steps_done)

    except Exception as exc:
        # Marca como falha sem sobrescrever texto já extraído
        try:
            session.sql(f"""
                UPDATE NEXUS_APP.CORE.DOCUMENTS
                SET processing_status = 'failed',
                    processed_at      = CURRENT_TIMESTAMP()
                WHERE document_id = '{p_document_id}'
                  AND org_id = '{p_org_id}'
            """).collect()
        except Exception:
            pass
        return f"ERROR: {str(exc)}"
$$;

GRANT USAGE ON PROCEDURE NEXUS_APP.AI.SP_PROCESS_DOCUMENT(VARCHAR, VARCHAR)
    TO ROLE NEXUS_ADMIN;
GRANT USAGE ON PROCEDURE NEXUS_APP.AI.SP_PROCESS_DOCUMENT(VARCHAR, VARCHAR)
    TO ROLE NEXUS_DATA_ENGINEER;

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
