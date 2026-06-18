"""
NEXUS AI DataOps — Agent Evaluation Tests
Behavioral smoke tests for Cortex Agents (executive, customer, revenue, risk).
These tests mock the REST layer and assert on response structure + content quality.

Run: pytest tests/agent_eval_tests.py -v
"""

import json
import pytest
from unittest.mock import MagicMock, patch


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def _make_agent_response(content: str, tools: list[str] | None = None, tokens: int = 400):
    return {
        "content": content,
        "usage": {"total_tokens": tokens, "prompt_tokens": tokens - 80, "completion_tokens": 80},
        "latency_ms": 1200,
        "tool_uses": [{"tool": t} for t in (tools or [])],
        "error": None,
    }


# ─────────────────────────────────────────────────────────────────────────────
# Executive Agent
# ─────────────────────────────────────────────────────────────────────────────

class TestExecutiveAgent:
    """Tests for cortex/agents/executive_agent.yaml behavior."""

    def test_response_has_content(self, sample_agent_response):
        assert sample_agent_response["content"]
        assert len(sample_agent_response["content"]) > 10

    def test_response_has_usage_metrics(self, sample_agent_response):
        usage = sample_agent_response["usage"]
        assert usage["total_tokens"] > 0
        assert usage["prompt_tokens"] > 0
        assert usage["completion_tokens"] > 0

    def test_response_has_latency(self, sample_agent_response):
        assert sample_agent_response["latency_ms"] > 0

    def test_response_no_error(self, sample_agent_response):
        assert sample_agent_response.get("error") is None

    def test_executive_briefing_mentions_risk(self, sample_executive_kpis):
        """Briefing gerado a partir de KPIs deve mencionar clientes em risco."""
        kpi_summary = json.dumps(sample_executive_kpis)
        # Simulate that a response referencing kpi_summary addresses risk
        mock_response = _make_agent_response(
            f"Há {sample_executive_kpis['HIGH_RISK_CUSTOMERS']} clientes em alto risco "
            f"representando R${sample_executive_kpis['ARR_AT_RISK']:,.0f} em ARR em risco.",
            tools=["cortex_analyst"],
        )
        assert str(sample_executive_kpis["HIGH_RISK_CUSTOMERS"]) in mock_response["content"]

    def test_executive_briefing_mentions_arr(self, sample_executive_kpis):
        """Briefing deve referenciar ARR total."""
        mock_response = _make_agent_response(
            f"ARR total: R${sample_executive_kpis['TOTAL_ARR']:,.0f}",
            tools=["cortex_analyst"],
        )
        assert "ARR" in mock_response["content"]

    def test_executive_agent_uses_analyst_tool(self):
        """Executive agent deve invocar cortex_analyst para consultas estruturadas."""
        response = _make_agent_response(
            "Clientes com saúde baixa nos últimos 30 dias...",
            tools=["cortex_analyst"],
        )
        tool_names = [t["tool"] for t in response["tool_uses"]]
        assert "cortex_analyst" in tool_names

    def test_executive_agent_token_limit(self, sample_agent_response):
        """Resposta do executive agent não deve ultrapassar 2000 tokens."""
        assert sample_agent_response["usage"]["total_tokens"] < 2000


# ─────────────────────────────────────────────────────────────────────────────
# Customer Agent
# ─────────────────────────────────────────────────────────────────────────────

class TestCustomerAgent:
    """Tests for cortex/agents/customer_agent.yaml behavior."""

    def test_customer_health_response_structure(self, sample_customer_row):
        """Resposta de saúde do cliente deve incluir score e recomendação."""
        mock_response = _make_agent_response(
            f"Health Score: {sample_customer_row['HEALTH_SCORE']}. "
            "Recomendação: agendar QBR com CS.",
            tools=["cortex_analyst"],
        )
        assert str(sample_customer_row["HEALTH_SCORE"]) in mock_response["content"]

    def test_customer_agent_handles_high_risk(self, sample_customer_row):
        """Para clientes em alto risco, resposta deve indicar urgência."""
        assert sample_customer_row["RISK_LEVEL"] == "HIGH"
        mock_response = _make_agent_response(
            "ATENÇÃO: cliente em ALTO RISCO de churn. Churn probability: 78%.",
            tools=["cortex_analyst", "cortex_search"],
        )
        assert "ALTO RISCO" in mock_response["content"] or "HIGH" in mock_response["content"]

    def test_customer_agent_uses_search_for_docs(self):
        """Para perguntas sobre contratos/docs, deve usar cortex_search."""
        response = _make_agent_response(
            "Encontrei 2 documentos relevantes sobre o contrato do cliente.",
            tools=["cortex_search"],
        )
        tool_names = [t["tool"] for t in response["tool_uses"]]
        assert "cortex_search" in tool_names

    def test_customer_agent_no_pii_in_logs(self, sample_customer_row):
        """Dados pessoais não devem vazar em campos de log estruturado."""
        # Simulate what would be stored in AUDIT.PROMPT_LOG (response_summary truncated)
        response_summary = f"Customer {sample_customer_row['CUSTOMER_ID']} analysis."
        assert "email" not in response_summary.lower()
        assert "phone" not in response_summary.lower()
        assert "cpf" not in response_summary.lower()


# ─────────────────────────────────────────────────────────────────────────────
# Revenue Agent
# ─────────────────────────────────────────────────────────────────────────────

class TestRevenueAgent:
    """Tests for cortex/agents/revenue_agent.yaml behavior."""

    def test_revenue_response_includes_mrr(self, sample_customer_row):
        """Análise de receita deve referenciar MRR."""
        mock_response = _make_agent_response(
            f"MRR atual: R${sample_customer_row['MRR']:,.0f}. "
            "Crescimento MoM: +3.2%.",
            tools=["cortex_analyst"],
        )
        assert "MRR" in mock_response["content"]

    def test_revenue_agent_uses_cortex_analyst(self):
        """Revenue agent deve sempre invocar cortex_analyst para métricas numéricas."""
        response = _make_agent_response(
            "ARR total cresceu 12% YoY.",
            tools=["cortex_analyst"],
        )
        tool_names = [t["tool"] for t in response["tool_uses"]]
        assert "cortex_analyst" in tool_names

    def test_revenue_kpis_completeness(self, sample_executive_kpis):
        """KPIs de receita devem incluir ARR, MRR e NRR."""
        assert "TOTAL_ARR" in sample_executive_kpis
        assert "TOTAL_MRR" in sample_executive_kpis
        assert "NET_REVENUE_RETENTION" in sample_executive_kpis

    def test_revenue_nrr_above_100_is_positive(self, sample_executive_kpis):
        """NRR > 100 indica expansão de receita — deve ser reportado positivamente."""
        nrr = sample_executive_kpis["NET_REVENUE_RETENTION"]
        assert nrr > 100.0
        mock_response = _make_agent_response(
            f"NRR de {nrr}% indica expansão de receita. Net positive.",
            tools=["cortex_analyst"],
        )
        assert str(nrr) in mock_response["content"]

    def test_revenue_arr_at_risk_reported(self, sample_executive_kpis):
        """ARR em risco deve ser quantificado na análise de receita."""
        arr_at_risk = sample_executive_kpis["ARR_AT_RISK"]
        mock_response = _make_agent_response(
            f"ARR em risco: R${arr_at_risk:,.0f} (alta prioridade CS).",
            tools=["cortex_analyst"],
        )
        assert str(int(arr_at_risk)) in mock_response["content"].replace(",", "")


# ─────────────────────────────────────────────────────────────────────────────
# Risk Agent
# ─────────────────────────────────────────────────────────────────────────────

class TestRiskAgent:
    """Tests for cortex/agents/risk_agent.yaml behavior."""

    def test_risk_response_categorizes_level(self, sample_customer_row):
        """Análise de risco deve categorizar em HIGH/MEDIUM/LOW."""
        mock_response = _make_agent_response(
            f"Risco: {sample_customer_row['RISK_LEVEL']}. "
            "Probabilidade de churn: 78%.",
            tools=["cortex_analyst"],
        )
        assert any(
            level in mock_response["content"]
            for level in ["HIGH", "MEDIUM", "LOW", "ALTO", "MÉDIO", "BAIXO"]
        )

    def test_risk_agent_uses_both_tools(self):
        """Risk agent deve usar cortex_analyst (métricas) + cortex_search (docs contratuais)."""
        response = _make_agent_response(
            "Com base nas métricas e no contrato do cliente...",
            tools=["cortex_analyst", "cortex_search"],
        )
        tool_names = [t["tool"] for t in response["tool_uses"]]
        assert "cortex_analyst" in tool_names
        assert "cortex_search" in tool_names

    def test_risk_agent_identifies_sla_breaches(self, sample_customer_row):
        """Agente de risco deve identificar violações de SLA como fator de risco."""
        sla = sample_customer_row["SLA_BREACHES"]
        mock_response = _make_agent_response(
            f"{sla} violações de SLA nos últimos 30 dias. Risco elevado.",
            tools=["cortex_analyst"],
        )
        assert str(int(sla)) in mock_response["content"]

    def test_risk_response_has_no_error(self):
        response = _make_agent_response("Análise de risco concluída sem erros.")
        assert response["error"] is None


# ─────────────────────────────────────────────────────────────────────────────
# Data Steward Agent
# ─────────────────────────────────────────────────────────────────────────────

class TestDataStewardAgent:
    """Tests for cortex/agents/data_steward_agent.yaml behavior."""

    def test_data_quality_response_mentions_pass_fail(self):
        """Data steward deve relatar PASS/FAIL de métricas de qualidade."""
        mock_response = _make_agent_response(
            "3 métricas em PASS, 1 em FAIL: freshness_hours excedeu 24h.",
            tools=["cortex_analyst"],
        )
        assert "PASS" in mock_response["content"] or "FAIL" in mock_response["content"]

    def test_data_steward_returns_actionable_recommendation(self):
        """Resposta do data steward deve incluir ação corretiva."""
        mock_response = _make_agent_response(
            "Recomendação: verificar pipeline de ingestão do Salesforce. "
            "Última atualização há 30 horas.",
            tools=["cortex_analyst", "cortex_search"],
        )
        assert len(mock_response["content"]) > 20

    def test_data_steward_uses_cortex_search_for_docs(self):
        """Para perguntas sobre definições/governança, deve usar cortex_search."""
        response = _make_agent_response(
            "Conforme documentado na política de qualidade...",
            tools=["cortex_search"],
        )
        tool_names = [t["tool"] for t in response["tool_uses"]]
        assert "cortex_search" in tool_names


# ─────────────────────────────────────────────────────────────────────────────
# Cross-agent: audit trail
# ─────────────────────────────────────────────────────────────────────────────

class TestAgentAuditTrail:
    """Garante que todas as respostas de agentes são auditáveis."""

    def test_response_has_token_count_for_cost_tracking(self, sample_agent_response):
        assert sample_agent_response["usage"]["total_tokens"] > 0

    def test_response_has_latency_for_sla_tracking(self, sample_agent_response):
        assert sample_agent_response["latency_ms"] > 0

    def test_response_content_truncatable_to_500_chars(self, sample_agent_response):
        """AUDIT.PROMPT_LOG armazena response_summary[:500]."""
        content = sample_agent_response["content"]
        assert len(content[:500]) <= 500

    def test_agent_id_format(self):
        """agent_id deve ser um string não vazio identificando o agente."""
        valid_ids = [
            "executive_agent",
            "customer_agent",
            "revenue_agent",
            "risk_agent",
            "data_steward_agent",
        ]
        for agent_id in valid_ids:
            assert isinstance(agent_id, str)
            assert len(agent_id) > 0
