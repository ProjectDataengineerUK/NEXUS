"""
NEXUS AI DataOps — KBS loader: Snowflake Core Documentation
Sprint 2 — P1: carrega docs do Snowflake (Dynamic Tables, Tasks, Cortex AI) no KBS
Roda no ambiente do provider via Airflow ou CLI.
"""

from __future__ import annotations

import json
import logging
import os
from dataclasses import dataclass

import requests
from chunker import chunk_markdown, Chunk

logger = logging.getLogger(__name__)

KB_NAME   = "snowflake_core"
BASE_URL  = "https://docs.snowflake.com"

SNOWFLAKE_DOC_PAGES = [
    ("/en/user-guide/dynamic-tables-about",         "Dynamic Tables — Overview"),
    ("/en/user-guide/dynamic-tables-create",        "Dynamic Tables — Creating"),
    ("/en/user-guide/dynamic-tables-refresh",       "Dynamic Tables — Refresh Modes"),
    ("/en/user-guide/tasks-intro",                  "Tasks — Introduction"),
    ("/en/user-guide/tasks-create",                 "Tasks — Creating"),
    ("/en/user-guide/snowpipe-streaming-overview",  "Snowpipe Streaming — Overview"),
    ("/en/user-guide/cortex-analyst",               "Cortex Analyst — Overview"),
    ("/en/user-guide/cortex-search-overview",       "Cortex Search — Overview"),
    ("/en/user-guide/cortex-agents",                "Cortex Agents — Overview"),
    ("/en/user-guide/security-access-control-overview", "RBAC — Overview"),
    ("/en/user-guide/row-access-policies",          "Row Access Policies"),
    ("/en/user-guide/masking-policies",             "Masking Policies"),
    ("/en/developer-guide/native-apps/native-apps-about", "Native App Framework"),
    ("/en/developer-guide/native-apps/setup-scripts", "Native App — Setup Scripts"),
]


@dataclass
class KBSLoader:
    snowflake_conn_str: str
    session: requests.Session = None

    def __post_init__(self):
        if self.session is None:
            self.session = requests.Session()
            self.session.headers.update({"User-Agent": "NEXUS-KBS-Loader/2.0"})

    def _fetch_page(self, path: str) -> str | None:
        url = f"{BASE_URL}{path}"
        try:
            resp = self.session.get(url, timeout=30)
            resp.raise_for_status()
            return resp.text
        except requests.RequestException as e:
            logger.warning("Falha ao buscar %s: %s", url, e)
            return None

    def _extract_text_from_html(self, html: str) -> str:
        import re
        text = re.sub(r"<script[^>]*>[\s\S]*?</script>", "", html)
        text = re.sub(r"<style[^>]*>[\s\S]*?</style>", "", text)
        text = re.sub(r"<[^>]+>", " ", text)
        text = re.sub(r"&nbsp;", " ", text)
        text = re.sub(r"&lt;", "<", text)
        text = re.sub(r"&gt;", ">", text)
        text = re.sub(r"&amp;", "&", text)
        text = re.sub(r"\s{3,}", "\n\n", text)
        return text.strip()

    def _load_source(self, source_id: str, path: str, title: str) -> list[Chunk]:
        html = self._fetch_page(path)
        if not html:
            return []
        text   = self._extract_text_from_html(html)
        chunks = chunk_markdown(text, title=title, url=f"{BASE_URL}{path}")
        logger.info("  %s → %d chunks", title, len(chunks))
        return chunks

    def _insert_chunks(self, source_id: str, chunks: list[Chunk]) -> int:
        from snowflake.connector import connect
        conn = connect(connection_string=self.snowflake_conn_str)
        cur  = conn.cursor()
        rows = [
            (
                source_id,
                KB_NAME,
                c.title,
                c.content,
                c.chunk_index,
                c.url,
                json.dumps(c.metadata),
            )
            for c in chunks
        ]
        cur.executemany(
            """
            INSERT INTO NEXUS_APP.KBS.DOCUMENTS
                (source_id, kb_name, title, content, chunk_index, url, doc_metadata)
            VALUES (%s, %s, %s, %s, %s, %s, PARSE_JSON(%s))
            """,
            rows,
        )
        cur.execute(
            "UPDATE NEXUS_APP.KBS.SOURCES SET last_loaded = CURRENT_TIMESTAMP() WHERE source_id = %s",
            (source_id,),
        )
        conn.commit()
        cur.close()
        conn.close()
        return len(rows)

    def _get_or_create_source(self, source_url: str) -> str:
        from snowflake.connector import connect
        conn = connect(connection_string=self.snowflake_conn_str)
        cur  = conn.cursor()
        cur.execute(
            "SELECT source_id FROM NEXUS_APP.KBS.SOURCES WHERE kb_name = %s AND source_url = %s",
            (KB_NAME, source_url),
        )
        row = cur.fetchone()
        if row:
            source_id = row[0]
        else:
            cur.execute(
                "INSERT INTO NEXUS_APP.KBS.SOURCES (kb_name, source_type, source_url) VALUES (%s, %s, %s)",
                (KB_NAME, "snowflake_docs", source_url),
            )
            cur.execute(
                "SELECT source_id FROM NEXUS_APP.KBS.SOURCES WHERE kb_name = %s AND source_url = %s",
                (KB_NAME, source_url),
            )
            source_id = cur.fetchone()[0]
        conn.commit()
        cur.close()
        conn.close()
        return source_id

    def run(self) -> int:
        logger.info("Iniciando carga de KBS: %s (%d páginas)", KB_NAME, len(SNOWFLAKE_DOC_PAGES))
        total = 0
        for path, title in SNOWFLAKE_DOC_PAGES:
            source_url = f"{BASE_URL}{path}"
            source_id  = self._get_or_create_source(source_url)
            chunks     = self._load_source(source_id, path, title)
            if chunks:
                inserted = self._insert_chunks(source_id, chunks)
                total   += inserted
        logger.info("KBS %s concluído: %d chunks inseridos", KB_NAME, total)
        return total


def main():
    conn_str = os.environ["SNOWFLAKE_CONNECTION_STRING"]
    loader   = KBSLoader(snowflake_conn_str=conn_str)
    loader.run()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    main()
