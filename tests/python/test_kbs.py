"""
NEXUS AI DataOps — KBS Tests (Sprint 2)
Testa o chunker e a estrutura dos loaders sem depender de credenciais reais.
"""

from __future__ import annotations

import pytest
from pathlib import Path

KBS_DIR = Path(__file__).parent.parent.parent / "pipelines" / "kbs"


@pytest.fixture(autouse=True)
def add_kbs_to_path():
    import sys
    sys.path.insert(0, str(KBS_DIR))
    yield
    sys.path.pop(0)


class TestChunker:
    def test_short_document_returns_single_chunk(self):
        from chunker import chunk_document
        chunks = chunk_document("Texto curto.", title="Test", url="http://example.com")
        assert len(chunks) == 1
        assert chunks[0].chunk_index == 0
        assert chunks[0].content == "Texto curto."

    def test_long_document_is_split(self):
        from chunker import chunk_document
        content = ("Parágrafo de texto. " * 20 + "\n\n") * 10
        chunks  = chunk_document(content, title="Test", url="http://example.com", chunk_size=500)
        assert len(chunks) > 1

    def test_empty_content_returns_empty_list(self):
        from chunker import chunk_document
        assert chunk_document("", title="T", url="http://x.com") == []
        assert chunk_document("   ", title="T", url="http://x.com") == []

    def test_chunks_preserve_metadata(self):
        from chunker import chunk_document
        meta   = {"source": "test", "version": "2.0"}
        chunks = chunk_document("Conteúdo de teste.", title="T", url="http://x.com", metadata=meta)
        assert chunks[0].metadata == meta

    def test_chunks_have_correct_indices(self):
        from chunker import chunk_document
        content = ("Frase longa. " * 30 + "\n\n") * 5
        chunks  = chunk_document(content, title="T", url="http://x.com", chunk_size=300)
        indices = [c.chunk_index for c in chunks]
        assert indices == list(range(len(chunks)))

    def test_chunk_markdown_strips_html_links(self):
        from chunker import chunk_markdown
        md     = "# Header\n\nTexto com [link](http://example.com) e **negrito**.\n\nPalavras normais."
        chunks = chunk_markdown(md, title="Test", url="http://x.com")
        assert all("<" not in c.content for c in chunks)

    def test_chunk_size_respected(self):
        from chunker import chunk_document
        content = "A" * 5000
        chunks  = chunk_document(content, title="T", url="http://x.com", chunk_size=1000)
        for c in chunks:
            assert len(c.content) <= 1100


class TestKBSLoaderStructure:
    def test_snowflake_loader_file_exists(self):
        assert (KBS_DIR / "load_kb_snowflake.py").exists()

    def test_cortex_loader_file_exists(self):
        assert (KBS_DIR / "load_kb_cortex.py").exists()

    def test_snowflake_loader_has_doc_pages(self):
        source = (KBS_DIR / "load_kb_snowflake.py").read_text()
        assert "SNOWFLAKE_DOC_PAGES" in source
        assert "dynamic-tables" in source
        assert "cortex" in source.lower()

    def test_cortex_loader_has_doc_pages(self):
        source = (KBS_DIR / "load_kb_cortex.py").read_text()
        assert "CORTEX_DOC_PAGES" in source
        assert "cortex-analyst" in source
        assert "cortex-search" in source

    def test_loaders_use_kbs_tables(self):
        for loader_file in ["load_kb_snowflake.py", "load_kb_cortex.py"]:
            source = (KBS_DIR / loader_file).read_text()
            assert "KBS.DOCUMENTS" in source, f"{loader_file} should write to KBS.DOCUMENTS"
            assert "KBS.SOURCES" in source, f"{loader_file} should update KBS.SOURCES"

    def test_loaders_use_chunker(self):
        for loader_file in ["load_kb_snowflake.py", "load_kb_cortex.py"]:
            source = (KBS_DIR / loader_file).read_text()
            assert "chunk_markdown" in source or "chunk_document" in source

    def test_kbs_refresh_dag_exists(self):
        dag_file = Path(__file__).parent.parent.parent / "airflow" / "dags" / "kbs_refresh_dag.py"
        assert dag_file.exists()
        source = dag_file.read_text()
        assert "kbs_refresh" in source
        assert "0 4 * * 0" in source


class TestKBSSchema:
    def test_kbs_schema_file_exists(self):
        assert (Path(__file__).parent.parent.parent / "snowflake" / "setup" / "16_kbs_schema.sql").exists()

    def test_kbs_schema_has_all_tables(self):
        source = (Path(__file__).parent.parent.parent / "snowflake" / "setup" / "16_kbs_schema.sql").read_text()
        for table in ["KBS.DOCUMENTS", "KBS.SOURCES", "KBS.SEARCH_LOGS"]:
            assert table in source

    def test_kbs_search_service_file_exists(self):
        search_file = (
            Path(__file__).parent.parent.parent
            / "snowflake" / "cortex" / "search_services" / "kbs_search.sql"
        )
        assert search_file.exists()
        source = search_file.read_text()
        assert "CORTEX SEARCH SERVICE" in source
        assert "KB_SEARCH_SERVICE" in source
