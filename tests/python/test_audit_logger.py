"""
NEXUS AI DataOps — Audit Logger Tests (Sprint 1 gap)
Testa a tabela AUDIT.ACTION_LOG e AUDIT.PROMPT_LOG sem banco real.
"""

from __future__ import annotations

import json
from pathlib import Path
from unittest.mock import MagicMock, call, patch

import pytest


class TestAuditSchema:
    """Verifica que o setup_script tem os DDLs de audit."""

    @pytest.fixture
    def setup_script(self) -> str:
        setup_path = (
            Path(__file__).parent.parent.parent
            / "snowflake" / "native_app" / "setup_script.sql"
        )
        return setup_path.read_text()

    def test_audit_action_log_exists(self, setup_script):
        assert "AUDIT.ACTION_LOG" in setup_script

    def test_audit_prompt_log_exists(self, setup_script):
        assert "AUDIT.PROMPT_LOG" in setup_script

    def test_audit_data_quality_results_exists(self, setup_script):
        assert "AUDIT.DATA_QUALITY_RESULTS" in setup_script

    def test_action_log_has_required_columns(self, setup_script):
        idx = setup_script.find("CREATE TABLE IF NOT EXISTS AUDIT.ACTION_LOG")
        assert idx != -1, "AUDIT.ACTION_LOG DDL not found"
        block = setup_script[idx:idx+1000]
        for col in ["org_id", "action_type", "created_at"]:
            assert col in block, f"Column {col!r} missing from ACTION_LOG DDL"

    def test_prompt_log_has_required_columns(self, setup_script):
        idx = setup_script.find("CREATE TABLE IF NOT EXISTS AUDIT.PROMPT_LOG")
        assert idx != -1, "AUDIT.PROMPT_LOG DDL not found"
        block = setup_script[idx:idx+1000]
        for col in ["org_id", "prompt_text", "created_at"]:
            assert col in block, f"Column {col!r} missing from PROMPT_LOG DDL"


class TestAuditLoggerOnboarding:
    """Verifica que o onboarding.py loga ações críticas."""

    @pytest.fixture
    def onboarding_source(self) -> str:
        path = (
            Path(__file__).parent.parent.parent
            / "app" / "streamlit" / "utils" / "onboarding.py"
        )
        return path.read_text()

    def test_map_reference_calls_register(self, onboarding_source):
        assert "REGISTER_REFERENCE" in onboarding_source

    def test_save_user_uses_merge(self, onboarding_source):
        assert "MERGE INTO CONFIG.ORG_USER_MAP" in onboarding_source

    def test_save_api_credential_exists(self, onboarding_source):
        assert "save_api_credential" in onboarding_source

    def test_no_hardcoded_credentials(self, onboarding_source):
        import re
        patterns = [r"password\s*=\s*['\"][^'\"]{6,}", r"api_key\s*=\s*['\"][^'\"]{10,}"]
        for pattern in patterns:
            assert not re.search(pattern, onboarding_source, re.IGNORECASE), \
                f"Hardcoded credential pattern found: {pattern}"


class TestAuditLoggerKBS:
    """Verifica que os loaders KBS logam no AUDIT.ACTION_LOG."""

    def test_stripe_dag_logs_to_audit(self):
        source = (
            Path(__file__).parent.parent.parent
            / "airflow" / "dags" / "salesforce_ingest_dag.py"
        ).read_text()
        assert "AUDIT.ACTION_LOG" in source

    def test_kbs_refresh_dag_logs_to_audit(self):
        source = (
            Path(__file__).parent.parent.parent
            / "airflow" / "dags" / "kbs_refresh_dag.py"
        ).read_text()
        assert "AUDIT.ACTION_LOG" in source


class TestAuditSearchLogs:
    """Verifica que o schema KBS inclui SEARCH_LOGS."""

    def test_search_logs_in_kbs_schema(self):
        source = (
            Path(__file__).parent.parent.parent
            / "snowflake" / "setup" / "16_kbs_schema.sql"
        ).read_text()
        assert "KBS.SEARCH_LOGS" in source
        assert "query_text" in source
        assert "latency_ms" in source
