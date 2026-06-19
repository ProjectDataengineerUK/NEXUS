"""
NEXUS AI DataOps — KBS loader: Cortex AI Documentation
Sprint 2 — P1: carrega docs de Cortex AI (Analyst, Search, Agents) no KBS
"""

from __future__ import annotations

import json
import logging
import os

import requests
from chunker import chunk_markdown, Chunk

logger = logging.getLogger(__name__)

KB_NAME   = "cortex_ai"
BASE_URL  = "https://docs.snowflake.com"

CORTEX_DOC_PAGES = [
    ("/en/user-guide/cortex-analyst",                    "Cortex Analyst — Overview"),
    ("/en/user-guide/cortex-analyst-semantic-model-spec", "Cortex Analyst — Semantic Model Spec"),
    ("/en/user-guide/cortex-search-overview",            "Cortex Search — Overview"),
    ("/en/user-guide/cortex-search-create",              "Cortex Search — Creating Services"),
    ("/en/user-guide/cortex-search-query",               "Cortex Search — Querying"),
    ("/en/user-guide/cortex-agents",                     "Cortex Agents — Overview"),
    ("/en/user-guide/cortex-agents-tools",               "Cortex Agents — Tools"),
    ("/en/sql-reference/functions/ai_complete",          "AI_COMPLETE Function"),
    ("/en/sql-reference/functions/ai_embed_text",        "AI_EMBED_TEXT Function"),
    ("/en/sql-reference/functions/ai_classify",          "AI_CLASSIFY Function"),
    ("/en/user-guide/snowflake-cortex/llm-functions",    "Cortex LLM Functions"),
    ("/en/user-guide/snowflake-cortex/rag-based-inference", "Cortex RAG — Overview"),
]

INLINE_CONTENT = {
    "/en/user-guide/cortex-agents-tools": """
## Cortex Agent Tools

Os Cortex Agents suportam os seguintes tipos de tools:

**cortex_analyst_textgeneration**: Gera SQL e responde perguntas sobre dados estruturados
usando um Semantic Model YAML. Configuração: `semantic_model_file` apontando para um YAML
em um stage Snowflake.

**cortex_search**: Busca semântica em documentos não estruturados usando um Cortex Search
Service. Configuração: `service_name` + `max_results` + filtros opcionais.

**sql_exec**: Executa queries SQL pré-autorizadas. Configuração: `warehouse` + lista de
`authorized_queries` com placeholders `{filter}`.

**data_to_chart**: Gera visualizações de dados.

Exemplo de configuração de agent com múltiplas tools:
```yaml
tools:
  - tool_type: cortex_analyst_textgeneration
    semantic_model_file: "@DB.SCHEMA.STAGE/model.yaml"
  - tool_type: cortex_search
    service_name: DB.SCHEMA.MY_SEARCH_SERVICE
    max_results: 5
```
    """,
}


class CortexKBSLoader:
    def __init__(self, snowflake_conn_str: str):
        self.snowflake_conn_str = snowflake_conn_str
        self.session = requests.Session()
        self.session.headers["User-Agent"] = "NEXUS-KBS-Loader/2.0"

    def _fetch_or_inline(self, path: str) -> str | None:
        if path in INLINE_CONTENT:
            return INLINE_CONTENT[path]
        try:
            resp = self.session.get(f"{BASE_URL}{path}", timeout=30)
            resp.raise_for_status()
            import re
            text = re.sub(r"<[^>]+>", " ", resp.text)
            text = re.sub(r"\s{3,}", "\n\n", text)
            return text.strip()
        except requests.RequestException as e:
            logger.warning("Falha ao buscar %s%s: %s", BASE_URL, path, e)
            return None

    def _upsert_source(self, source_url: str) -> str:
        from snowflake.connector import connect
        conn = connect(connection_string=self.snowflake_conn_str)
        cur  = conn.cursor()
        cur.execute(
            "SELECT source_id FROM NEXUS_APP.KBS.SOURCES WHERE kb_name = %s AND source_url = %s",
            (KB_NAME, source_url),
        )
        row = cur.fetchone()
        if not row:
            cur.execute(
                "INSERT INTO NEXUS_APP.KBS.SOURCES (kb_name, source_type, source_url) VALUES (%s, %s, %s)",
                (KB_NAME, "cortex_docs", source_url),
            )
            cur.execute(
                "SELECT source_id FROM NEXUS_APP.KBS.SOURCES WHERE kb_name = %s AND source_url = %s",
                (KB_NAME, source_url),
            )
            row = cur.fetchone()
        source_id = row[0]
        conn.commit()
        cur.close()
        conn.close()
        return source_id

    def _bulk_insert(self, source_id: str, chunks: list[Chunk]) -> None:
        from snowflake.connector import connect
        conn = connect(connection_string=self.snowflake_conn_str)
        cur  = conn.cursor()
        cur.executemany(
            """
            INSERT INTO NEXUS_APP.KBS.DOCUMENTS
                (source_id, kb_name, title, content, chunk_index, url, doc_metadata)
            VALUES (%s, %s, %s, %s, %s, %s, PARSE_JSON(%s))
            """,
            [
                (source_id, KB_NAME, c.title, c.content, c.chunk_index, c.url, json.dumps(c.metadata))
                for c in chunks
            ],
        )
        cur.execute(
            "UPDATE NEXUS_APP.KBS.SOURCES SET last_loaded = CURRENT_TIMESTAMP() WHERE source_id = %s",
            (source_id,),
        )
        conn.commit()
        cur.close()
        conn.close()

    def run(self) -> int:
        logger.info("Iniciando carga de KBS: %s", KB_NAME)
        total = 0
        for path, title in CORTEX_DOC_PAGES:
            source_url = f"{BASE_URL}{path}"
            content    = self._fetch_or_inline(path)
            if not content:
                continue
            chunks    = chunk_markdown(content, title=title, url=source_url)
            source_id = self._upsert_source(source_url)
            self._bulk_insert(source_id, chunks)
            total += len(chunks)
            logger.info("  %s → %d chunks", title, len(chunks))
        logger.info("KBS %s concluído: %d chunks", KB_NAME, total)
        return total


def main():
    conn_str = os.environ["SNOWFLAKE_CONNECTION_STRING"]
    CortexKBSLoader(conn_str).run()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    main()
