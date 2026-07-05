"""Tests for Sprint 3 semantic model YAMLs and cortex_analyst helper."""

import importlib
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest
import yaml

REPO_ROOT = Path(__file__).parent.parent.parent
MODELS_DIR = REPO_ROOT / "snowflake" / "cortex" / "semantic_models"

REQUIRED_MODELS = [
    "executive_kpis.yaml",
    "nexus_revenue.yaml",
    "customer_360.yaml",
    "operations_model.yaml",
    "revenue_opportunity_model.yaml",
]

SPRINT3_MODELS = ["operations_model.yaml", "revenue_opportunity_model.yaml"]


# ── Helpers ───────────────────────────────────────────────────────────────────

def load_model(filename: str) -> dict:
    path = MODELS_DIR / filename
    return yaml.safe_load(path.read_text(encoding="utf-8"))


# ── AT-110 proxy: YAML files exist ───────────────────────────────────────────

class TestSemanticModelFiles:
    def test_all_required_models_exist(self):
        for fname in REQUIRED_MODELS:
            assert (MODELS_DIR / fname).exists(), f"{fname} não encontrado em {MODELS_DIR}"

    def test_sprint3_models_exist(self):
        for fname in SPRINT3_MODELS:
            assert (MODELS_DIR / fname).exists(), f"Sprint 3 model {fname} ausente"


# ── Structure validation ──────────────────────────────────────────────────────

class TestSemanticModelStructure:
    @pytest.mark.parametrize("fname", REQUIRED_MODELS)
    def test_has_required_top_level_keys(self, fname):
        model = load_model(fname)
        assert "name" in model, f"{fname}: campo 'name' ausente"
        assert "description" in model, f"{fname}: campo 'description' ausente"
        assert "tables" in model, f"{fname}: campo 'tables' ausente"
        assert isinstance(model["tables"], list), f"{fname}: 'tables' deve ser lista"
        assert len(model["tables"]) >= 1, f"{fname}: deve ter ao menos 1 tabela"

    @pytest.mark.parametrize("fname", REQUIRED_MODELS)
    def test_each_table_has_base_table(self, fname):
        model = load_model(fname)
        for table in model["tables"]:
            assert "base_table" in table, f"{fname}: tabela '{table.get('name')}' sem base_table"
            bt = table["base_table"]
            assert "database" in bt and "schema" in bt and "table" in bt, \
                f"{fname}: base_table de '{table.get('name')}' incompleto"

    @pytest.mark.parametrize("fname", REQUIRED_MODELS)
    def test_each_table_has_dimensions_and_measures(self, fname):
        model = load_model(fname)
        for table in model["tables"]:
            assert "dimensions" in table and len(table["dimensions"]) >= 1, \
                f"{fname}: tabela '{table.get('name')}' sem dimensions"
            assert "measures" in table and len(table["measures"]) >= 1, \
                f"{fname}: tabela '{table.get('name')}' sem measures"

    @pytest.mark.parametrize("fname", REQUIRED_MODELS)
    def test_has_verified_queries(self, fname):
        model = load_model(fname)
        assert "verified_queries" in model, f"{fname}: sem verified_queries"
        assert len(model["verified_queries"]) >= 2, \
            f"{fname}: deve ter ao menos 2 verified_queries"

    @pytest.mark.parametrize("fname", REQUIRED_MODELS)
    def test_verified_queries_have_sql(self, fname):
        model = load_model(fname)
        for vq in model["verified_queries"]:
            assert "sql" in vq and vq["sql"].strip(), \
                f"{fname}: verified_query '{vq.get('name')}' sem SQL"
            assert "question" in vq and vq["question"].strip(), \
                f"{fname}: verified_query '{vq.get('name')}' sem question"


# ── operations_model.yaml specific ───────────────────────────────────────────

class TestOperationsModel:
    def test_covers_tickets_table(self):
        model = load_model("operations_model.yaml")
        table_names = [t["base_table"]["table"] for t in model["tables"]]
        assert "TICKETS" in table_names, "operations_model deve cobrir CORE.TICKETS"

    def test_covers_interactions_table(self):
        model = load_model("operations_model.yaml")
        table_names = [t["base_table"]["table"] for t in model["tables"]]
        assert "INTERACTIONS" in table_names, "operations_model deve cobrir CORE.INTERACTIONS"

    def test_covers_customer_health_table(self):
        model = load_model("operations_model.yaml")
        table_names = [t["base_table"]["table"] for t in model["tables"]]
        assert "DT_CUSTOMER_HEALTH" in table_names, "operations_model deve cobrir MART.DT_CUSTOMER_HEALTH"

    def test_tickets_has_status_dimension(self):
        model = load_model("operations_model.yaml")
        tickets = next(t for t in model["tables"] if t["base_table"]["table"] == "TICKETS")
        dim_names = [d["name"] for d in tickets["dimensions"]]
        assert "status" in dim_names, "tickets deve ter dimension 'status'"

    def test_tickets_has_resolution_measure(self):
        model = load_model("operations_model.yaml")
        tickets = next(t for t in model["tables"] if t["base_table"]["table"] == "TICKETS")
        measure_names = [m["name"] for m in tickets["measures"]]
        assert any("resolution" in n for n in measure_names), \
            "tickets deve ter measure de tempo de resolução"

    def test_has_relationships(self):
        model = load_model("operations_model.yaml")
        assert "relationships" in model and len(model["relationships"]) >= 1


# ── revenue_opportunity_model.yaml specific ───────────────────────────────────

class TestRevenueOpportunityModel:
    def test_covers_revenue_opportunity_score(self):
        model = load_model("revenue_opportunity_model.yaml")
        table_names = [t["base_table"]["table"] for t in model["tables"]]
        assert "REVENUE_OPPORTUNITY_SCORE" in table_names

    def test_covers_revenue_movement(self):
        model = load_model("revenue_opportunity_model.yaml")
        table_names = [t["base_table"]["table"] for t in model["tables"]]
        assert "DT_REVENUE_MOVEMENT" in table_names

    def test_covers_products(self):
        model = load_model("revenue_opportunity_model.yaml")
        table_names = [t["base_table"]["table"] for t in model["tables"]]
        assert "PRODUCTS" in table_names

    def test_has_pipeline_measure(self):
        model = load_model("revenue_opportunity_model.yaml")
        opp_table = next(
            t for t in model["tables"] if t["base_table"]["table"] == "REVENUE_OPPORTUNITY_SCORE"
        )
        measure_names = [m["name"] for m in opp_table["measures"]]
        assert any("pipeline" in n for n in measure_names), \
            "revenue_opportunity deve ter measure de pipeline total"


# ── customer_360.yaml — interactions table added in Sprint 3 ─────────────────

class TestCustomer360ModelUpdate:
    def test_interactions_table_added(self):
        model = load_model("customer_360.yaml")
        table_names = [t["base_table"]["table"] for t in model["tables"]]
        assert "INTERACTIONS" in table_names, \
            "customer_360.yaml deve incluir CORE.INTERACTIONS (Sprint 3)"

    def test_customer_interactions_relationship_exists(self):
        model = load_model("customer_360.yaml")
        assert "relationships" in model
        rel_names = [r["name"] for r in model["relationships"]]
        assert "customer_interactions" in rel_names


# ── operations_agent.yaml path fix ───────────────────────────────────────────

class TestOperationsAgentPath:
    def test_operations_agent_uses_correct_stage_path(self):
        agent_path = REPO_ROOT / "snowflake" / "cortex" / "agents" / "operations_agent.yaml"
        content = agent_path.read_text(encoding="utf-8")
        assert "CONFIG.NEXUS_STAGE" not in content, \
            "operations_agent.yaml ainda usa o stage path errado CONFIG.NEXUS_STAGE"
        assert "@NEXUS_APP.CORE.SEMANTIC_STAGE/operations_model.yaml" in content, \
            "operations_agent.yaml deve referenciar @NEXUS_APP.CORE.SEMANTIC_STAGE/operations_model.yaml"


# ── cortex_analyst.py helper ─────────────────────────────────────────────────

class TestCortexAnalystHelper:
    def test_helper_module_importable(self):
        utils_path = str(REPO_ROOT / "app" / "streamlit")
        if utils_path not in sys.path:
            sys.path.insert(0, utils_path)

        st_mock = MagicMock()
        pd_mock = MagicMock()
        snowflake_mock = MagicMock()

        with patch.dict("sys.modules", {
            "streamlit": st_mock,
            "pandas": pd_mock,
            "snowflake": snowflake_mock,
            "snowflake.snowpark": MagicMock(),
            "snowflake.snowpark.context": MagicMock(),
            "utils.snowflake_client": MagicMock(),
        }):
            spec = importlib.util.spec_from_file_location(
                "cortex_analyst",
                REPO_ROOT / "app" / "streamlit" / "utils" / "cortex_analyst.py",
            )
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)

            assert hasattr(module, "ask_analyst"), "cortex_analyst deve expor ask_analyst()"
            assert hasattr(module, "render_analyst_widget"), \
                "cortex_analyst deve expor render_analyst_widget()"

    def test_ask_analyst_delegates_to_client(self):
        utils_path = str(REPO_ROOT / "app" / "streamlit")
        if utils_path not in sys.path:
            sys.path.insert(0, utils_path)

        mock_client = MagicMock()
        mock_client.call_cortex_analyst.return_value = {
            "text": "resultado", "sql": "SELECT 1", "latency_ms": 100, "error": None
        }

        with patch.dict("sys.modules", {
            "streamlit": MagicMock(),
            "pandas": MagicMock(),
            "utils.snowflake_client": mock_client,
        }):
            spec = importlib.util.spec_from_file_location(
                "cortex_analyst2",
                REPO_ROOT / "app" / "streamlit" / "utils" / "cortex_analyst.py",
            )
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)

            module.ask_analyst("test question", "@CORE.SEMANTIC_STAGE/operations_model.yaml")
            mock_client.call_cortex_analyst.assert_called_once_with(
                "test question", "@CORE.SEMANTIC_STAGE/operations_model.yaml"
            )


# ── upload_semantic_models.sh ─────────────────────────────────────────────────

class TestUploadScript:
    def test_upload_script_exists(self):
        script = REPO_ROOT / "scripts" / "upload_semantic_models.sh"
        assert script.exists(), "scripts/upload_semantic_models.sh não encontrado"

    def test_upload_script_references_correct_stage(self):
        script = REPO_ROOT / "scripts" / "upload_semantic_models.sh"
        content = script.read_text(encoding="utf-8")
        assert "@NEXUS_APP.CORE.SEMANTIC_STAGE" in content

    def test_upload_script_is_executable_or_has_shebang(self):
        script = REPO_ROOT / "scripts" / "upload_semantic_models.sh"
        content = script.read_text(encoding="utf-8")
        assert content.startswith("#!/"), "Script deve ter shebang (#!)"
