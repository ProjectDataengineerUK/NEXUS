"""
NEXUS AI DataOps — Pipeline Tests (Sprint 2)
Testa os DAGs do Airflow (estrutura e lógica) sem depender de credentials reais.
"""

import importlib
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

DAGS_DIR = Path(__file__).parent.parent.parent / "airflow" / "dags"


def _import_dag(dag_file: str):
    spec = importlib.util.spec_from_file_location(dag_file, DAGS_DIR / dag_file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture(autouse=True)
def mock_airflow_deps():
    mocks = {
        "airflow":                                           MagicMock(),
        "airflow.decorators":                               MagicMock(),
        "airflow.models":                                   MagicMock(),
        "airflow.providers":                                MagicMock(),
        "airflow.providers.snowflake":                      MagicMock(),
        "airflow.providers.snowflake.hooks":                MagicMock(),
        "airflow.providers.snowflake.hooks.snowflake":      MagicMock(),
        "requests":                                         MagicMock(),
        "oracledb":                                         MagicMock(),
    }
    with patch.dict(sys.modules, mocks):
        yield mocks


class TestSalesforceDAG:
    def test_dag_file_exists(self):
        assert (DAGS_DIR / "salesforce_ingest_dag.py").exists()

    def test_dag_has_required_constants(self):
        source = (DAGS_DIR / "salesforce_ingest_dag.py").read_text()
        assert "SALESFORCE_OBJECTS" in source
        assert "Account" in source
        assert "Contact" in source
        assert "Opportunity" in source
        assert "snowflake_nexus" in source

    def test_dag_uses_taskflow_api(self):
        source = (DAGS_DIR / "salesforce_ingest_dag.py").read_text()
        assert "@task" in source
        assert "@dag" in source

    def test_dag_has_retry_config(self):
        source = (DAGS_DIR / "salesforce_ingest_dag.py").read_text()
        assert "retries" in source
        assert "retry_delay" in source

    def test_dag_loads_to_snowflake(self):
        source = (DAGS_DIR / "salesforce_ingest_dag.py").read_text()
        assert "STAGING.SF_" in source or "load_to_snowflake" in source

    def test_dag_logs_audit(self):
        source = (DAGS_DIR / "salesforce_ingest_dag.py").read_text()
        assert "AUDIT.ACTION_LOG" in source


class TestZendeskDAG:
    def test_dag_file_exists(self):
        assert (DAGS_DIR / "zendesk_ingest_dag.py").exists()

    def test_dag_covers_tickets(self):
        source = (DAGS_DIR / "zendesk_ingest_dag.py").read_text()
        assert "tickets" in source
        assert "CORE.TICKETS" in source

    def test_dag_has_merge_logic(self):
        source = (DAGS_DIR / "zendesk_ingest_dag.py").read_text()
        assert "MERGE INTO" in source

    def test_dag_uses_api_pagination(self):
        source = (DAGS_DIR / "zendesk_ingest_dag.py").read_text()
        assert "has_more" in source or "next" in source


class TestStripeDAG:
    def test_dag_file_exists(self):
        assert (DAGS_DIR / "stripe_ingest_dag.py").exists()

    def test_dag_covers_core_resources(self):
        source = (DAGS_DIR / "stripe_ingest_dag.py").read_text()
        for resource in ["customers", "subscriptions", "invoices", "charges"]:
            assert resource in source, f"Resource {resource!r} not found in Stripe DAG"

    def test_dag_merges_to_subscriptions(self):
        source = (DAGS_DIR / "stripe_ingest_dag.py").read_text()
        assert "CORE.SUBSCRIPTIONS" in source

    def test_dag_merges_to_transactions(self):
        source = (DAGS_DIR / "stripe_ingest_dag.py").read_text()
        assert "CORE.TRANSACTIONS" in source

    def test_dag_handles_pagination(self):
        source = (DAGS_DIR / "stripe_ingest_dag.py").read_text()
        assert "starting_after" in source or "has_more" in source

    def test_dag_uses_secret_key_variable(self):
        source = (DAGS_DIR / "stripe_ingest_dag.py").read_text()
        assert "STRIPE_SECRET_KEY" in source


class TestSAPDAG:
    def test_dag_file_exists(self):
        assert (DAGS_DIR / "sap_ingest_dag.py").exists()

    def test_dag_covers_entities(self):
        source = (DAGS_DIR / "sap_ingest_dag.py").read_text()
        for entity in ["customers", "invoices", "orders"]:
            assert entity in source, f"Entity {entity!r} not found in SAP DAG"

    def test_dag_uses_odata_variables(self):
        source = (DAGS_DIR / "sap_ingest_dag.py").read_text()
        assert "SAP_ODATA_BASE_URL" in source
        assert "SAP_USER" in source
        assert "SAP_PASSWORD" in source

    def test_dag_loads_to_staging_only(self):
        source = (DAGS_DIR / "sap_ingest_dag.py").read_text()
        assert "STAGING.SAP_" in source
        assert "MERGE INTO" not in source, "MERGE deve ser feito pela Task de CDC no Snowflake, não no DAG"

    def test_dag_uses_taskflow_api(self):
        source = (DAGS_DIR / "sap_ingest_dag.py").read_text()
        assert "@task" in source
        assert "@dag" in source

    def test_dag_has_retry_config(self):
        source = (DAGS_DIR / "sap_ingest_dag.py").read_text()
        assert "retries" in source
        assert "retry_delay" in source


class TestOracleDAG:
    def test_dag_file_exists(self):
        assert (DAGS_DIR / "oracle_ingest_dag.py").exists()

    def test_dag_covers_tables(self):
        source = (DAGS_DIR / "oracle_ingest_dag.py").read_text()
        for table in ["customers", "orders", "invoices"]:
            assert table in source, f"Table {table!r} not found in Oracle DAG"

    def test_dag_uses_oracledb_thin_mode(self):
        source = (DAGS_DIR / "oracle_ingest_dag.py").read_text()
        assert "import oracledb" in source
        assert "oracledb.connect" in source

    def test_dag_uses_connection_variables(self):
        source = (DAGS_DIR / "oracle_ingest_dag.py").read_text()
        assert "ORACLE_DSN" in source
        assert "ORACLE_USER" in source
        assert "ORACLE_PASSWORD" in source

    def test_dag_loads_to_staging_only(self):
        source = (DAGS_DIR / "oracle_ingest_dag.py").read_text()
        assert "STAGING.ORACLE_" in source
        assert "MERGE INTO" not in source, "MERGE deve ser feito pela Task de CDC no Snowflake, não no DAG"


class TestHubSpotDAG:
    def test_dag_file_exists(self):
        assert (DAGS_DIR / "hubspot_ingest_dag.py").exists()

    def test_dag_covers_objects(self):
        source = (DAGS_DIR / "hubspot_ingest_dag.py").read_text()
        for obj in ["contacts", "deals", "companies"]:
            assert obj in source, f"Object {obj!r} not found in HubSpot DAG"

    def test_dag_uses_access_token_variable(self):
        source = (DAGS_DIR / "hubspot_ingest_dag.py").read_text()
        assert "HUBSPOT_ACCESS_TOKEN" in source

    def test_dag_uses_v3_pagination(self):
        source = (DAGS_DIR / "hubspot_ingest_dag.py").read_text()
        assert "crm/v3/objects" in source
        assert "after" in source

    def test_dag_loads_to_staging_only(self):
        source = (DAGS_DIR / "hubspot_ingest_dag.py").read_text()
        assert "STAGING.HUBSPOT_" in source
        assert "MERGE INTO" not in source, "MERGE deve ser feito pela Task de CDC no Snowflake, não no DAG"


class TestAirflowConnection:
    def test_connection_file_exists(self):
        conn_file = Path(__file__).parent.parent.parent / "airflow" / "connections" / "snowflake_default.json"
        assert conn_file.exists()

    def test_connection_has_required_fields(self):
        import json
        conn_file = Path(__file__).parent.parent.parent / "airflow" / "connections" / "snowflake_default.json"
        conn = json.loads(conn_file.read_text())
        assert conn["conn_id"] == "snowflake_nexus"
        assert conn["conn_type"] == "snowflake"
        assert "extra" in conn
        assert "warehouse" in conn["extra"]

    def test_requirements_file_exists(self):
        req_file = Path(__file__).parent.parent.parent / "airflow" / "requirements.txt"
        assert req_file.exists()
        content = req_file.read_text()
        assert "apache-airflow" in content
        assert "apache-airflow-providers-snowflake" in content
