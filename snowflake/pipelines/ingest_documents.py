"""
NEXUS AI DataOps — Document Ingestion Pipeline
Monitora CORE.DOC_STAGE, extrai texto com Document AI functions
(AI_EXTRACT / AI_SUMMARIZE) e popula CORE.DOCUMENTS + AI.DOCUMENT_CHUNKS.
"""

import logging
import os

from snowflake.snowpark import Session

logger = logging.getLogger(__name__)

ORG_ID     = os.getenv("NEXUS_ORG_ID", "ORG-DEMO-001")
CHUNK_SIZE = 1500   # chars por chunk
OVERLAP    = 200    # chars de sobreposição entre chunks


def _chunk_text(text: str, chunk_size: int = CHUNK_SIZE, overlap: int = OVERLAP) -> list[str]:
    """Divide texto em chunks com sobreposição."""
    if not text or len(text) <= chunk_size:
        return [text] if text else []
    chunks, start = [], 0
    while start < len(text):
        end = min(start + chunk_size, len(text))
        chunks.append(text[start:end])
        start += chunk_size - overlap
    return chunks


def process_pending_documents(session: Session, org_id: str = ORG_ID) -> str:
    """
    1. Lista arquivos novos no DOC_STAGE via DIRECTORY TABLE.
    2. Para cada arquivo: extrai texto com AI_EXTRACT, registra em CORE.DOCUMENTS.
    3. Divide em chunks e insere em AI.DOCUMENT_CHUNKS.
    """
    # Identifica arquivos staged ainda não processados
    staged = session.sql("""
        SELECT f.relative_path, f.file_url, f.size
        FROM DIRECTORY(@NEXUS_APP.CORE.DOC_STAGE) f
        LEFT JOIN NEXUS_APP.CORE.DOCUMENTS d
            ON d.stage_path = f.relative_path AND d.org_id = ?
        WHERE d.document_id IS NULL
        LIMIT 50
    """, params=[org_id]).collect()

    if not staged:
        return f"OK: nenhum documento novo no DOC_STAGE para {org_id}"

    docs_created   = 0
    chunks_created = 0

    for row in staged:
        path     = row["RELATIVE_PATH"]
        doc_type = _infer_type(path)
        doc_name  = path.split("/")[-1]

        # Extrai texto via Cortex Document AI
        try:
            extract = session.sql(f"""
                SELECT SNOWFLAKE.CORTEX.PARSE_DOCUMENT(
                    BUILD_SCOPED_FILE_URL(@NEXUS_APP.CORE.DOC_STAGE, '{path}'),
                    {{'mode': 'LAYOUT'}}
                ) AS result
            """).collect()
            extracted_text = extract[0]["RESULT"].get("content", "") if extract else ""
        except Exception as e:
            logger.warning("parse_document failed for %s: %s — using empty text", path, e)
            extracted_text = ""

        # Summarize via Cortex Complete
        summary = ""
        if extracted_text:
            try:
                s = session.sql("""
                    SELECT SNOWFLAKE.CORTEX.SUMMARIZE(?) AS s
                """, params=[extracted_text[:8000]]).collect()
                summary = s[0]["S"] if s else ""
            except Exception:
                pass

        # Registra documento
        doc_id = session.sql("""
            INSERT INTO NEXUS_APP.CORE.DOCUMENTS
                (org_id, document_name, document_type, stage_path,
                 extracted_text, summary, processing_status)
            VALUES (?, ?, ?, ?, ?, ?, 'indexed')
            RETURNING document_id
        """, params=[org_id, doc_name, doc_type, path, extracted_text, summary]).collect()

        if not doc_id:
            continue
        document_id = doc_id[0]["DOCUMENT_ID"]
        docs_created += 1

        # Gera chunks
        chunks = _chunk_text(extracted_text)
        for idx, chunk in enumerate(chunks):
            try:
                session.sql("""
                    INSERT INTO NEXUS_APP.AI.DOCUMENT_CHUNKS
                        (document_id, org_id, document_name, document_type,
                         chunk_index, chunk_text, char_count)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                """, params=[
                    document_id, org_id, doc_name, doc_type,
                    idx, chunk, len(chunk),
                ]).collect()
                chunks_created += 1
            except Exception as e:
                logger.warning("chunk insert failed: %s", e)

    return (
        f"OK: {docs_created} documentos processados, "
        f"{chunks_created} chunks criados para {org_id}"
    )


def _infer_type(path: str) -> str:
    ext = path.lower().rsplit(".", 1)[-1]
    return {"pdf": "contract", "docx": "report", "xlsx": "financial",
            "txt": "note"}.get(ext, "other")


def run(session: Session, org_id: str = ORG_ID) -> str:
    return process_pending_documents(session, org_id)


if __name__ == "__main__":
    session = Session.builder.config("connection_name", "nexus_dev").create()
    print(run(session))
    session.close()
