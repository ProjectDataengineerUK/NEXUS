"""
NEXUS AI DataOps — Embedding Pipeline
Gera embeddings de AI.DOCUMENT_CHUNKS via SNOWFLAKE.CORTEX.EMBED_TEXT_1024.
Escreve vetores em AI.EMBEDDINGS para suporte a busca semântica densa.
Execução: Task a cada 30min sobre chunks sem embedding.
"""

from snowflake.snowpark import Session
from snowflake.snowpark.functions import col, lit, current_timestamp

ORG_ID        = "ORG-DEMO-001"
MODEL_NAME    = "e5-base-v2"
BATCH_SIZE    = 100   # chunks por batch para evitar timeout
MAX_CHUNKS    = 1000  # limite por execução


def run(session: Session, org_id: str = ORG_ID) -> str:
    """
    Gera embeddings para chunks sem vetor em AI.EMBEDDINGS.
    Usa SNOWFLAKE.CORTEX.EMBED_TEXT_1024 nativamente no Snowflake.
    """

    # ── Identifica chunks sem embedding ──────────────────────────────────────
    pending = session.sql("""
        SELECT c.chunk_id, c.document_id, c.org_id, c.chunk_text
        FROM AI.DOCUMENT_CHUNKS c
        LEFT JOIN AI.EMBEDDINGS e ON e.chunk_id = c.chunk_id
        WHERE c.org_id = ?
          AND e.chunk_id IS NULL
          AND c.chunk_text IS NOT NULL
          AND LENGTH(TRIM(c.chunk_text)) > 20
        ORDER BY c.created_at
        LIMIT ?
    """, params=[org_id, MAX_CHUNKS]).collect()

    if not pending:
        return f"OK: nenhum chunk pendente de embedding para {org_id}"

    # ── Gera embeddings em batches ────────────────────────────────────────────
    inserted = 0
    errors   = 0

    for i in range(0, len(pending), BATCH_SIZE):
        batch = pending[i:i + BATCH_SIZE]

        for row in batch:
            chunk_id    = row["CHUNK_ID"]
            document_id = row["DOCUMENT_ID"]
            chunk_text  = row["CHUNK_TEXT"].replace("'", "''")[:8000]

            try:
                session.sql(f"""
                    INSERT INTO AI.EMBEDDINGS
                        (chunk_id, org_id, document_id, embedding, model_name)
                    SELECT
                        '{chunk_id}',
                        '{org_id}',
                        '{document_id}',
                        SNOWFLAKE.CORTEX.EMBED_TEXT_1024('{MODEL_NAME}', '{chunk_text}'),
                        '{MODEL_NAME}'
                """).collect()
                inserted += 1
            except Exception:
                errors += 1
                continue

    return (
        f"OK: {inserted} embeddings gerados para {org_id} "
        f"(model={MODEL_NAME}, erros={errors})"
    )


def run_all_orgs(session: Session) -> str:
    """Processa todos os orgs com chunks pendentes."""
    orgs = session.sql("""
        SELECT DISTINCT c.org_id
        FROM AI.DOCUMENT_CHUNKS c
        LEFT JOIN AI.EMBEDDINGS e ON e.chunk_id = c.chunk_id
        WHERE e.chunk_id IS NULL
        LIMIT 20
    """).collect()

    results = []
    for row in orgs:
        results.append(run(session, org_id=row["ORG_ID"]))

    return "\n".join(results) if results else "OK: nenhum chunk pendente em nenhum org"


if __name__ == "__main__":
    from snowflake.snowpark import Session
    session = Session.builder.config("connection_name", "nexus_dev").create()
    print(run(session))
    session.close()
