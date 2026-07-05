"""Shared Cortex Analyst helper — NL→SQL widget reutilizável."""

from __future__ import annotations

import pandas as pd
import streamlit as st

from utils.snowflake_client import call_cortex_analyst as _call_analyst
from utils.snowflake_client import run_query as _run_query


def ask_analyst(question: str, model_file: str) -> dict:
    """Call Cortex Analyst and return a normalised result dict.

    Returns:
        {"text": str, "sql": str | None, "latency_ms": int, "error": str | None}
    """
    return _call_analyst(question, model_file)


def _auto_chart(df: pd.DataFrame, question: str) -> None:
    if df.empty or len(df.columns) < 2:
        return
    num_cols = df.select_dtypes(include="number").columns.tolist()
    cat_cols = df.select_dtypes(exclude="number").columns.tolist()
    if not num_cols:
        return
    q = question.lower()
    line_keywords = ["tendência", "trend", "histórico", "ao longo", "por mês", "por dia", "evolução"]
    date_cols = [c for c in df.columns if any(k in c.lower() for k in ("date", "month", "day", "mes", "dia"))]
    if any(k in q for k in line_keywords) and date_cols:
        st.line_chart(df.set_index(date_cols[0])[num_cols[:3]])
    elif cat_cols and len(df) <= 25:
        st.bar_chart(df.set_index(cat_cols[0])[num_cols[0]])


def render_analyst_widget(
    model_file: str,
    suggestions: list[str] | None = None,
    key_prefix: str = "analyst",
    placeholder: str = "Faça uma pergunta sobre seus dados…",
) -> None:
    """Full NL→SQL widget: suggestions → chat input → result → SQL expander → auto chart."""
    history_key = f"{key_prefix}_history"
    if history_key not in st.session_state:
        st.session_state[history_key] = []

    history: list[dict] = st.session_state[history_key]

    if suggestions and not history:
        cols = st.columns(min(len(suggestions), 3))
        for i, sug in enumerate(suggestions):
            if cols[i % 3].button(sug, key=f"{key_prefix}_sug_{i}"):
                history.append({"role": "user", "content": sug})
                st.rerun()

    for msg in history:
        with st.chat_message(msg["role"]):
            st.markdown(msg["content"])
            if msg.get("sql"):
                with st.expander("🔍 SQL gerado"):
                    st.code(msg["sql"], language="sql")
            if msg.get("df") is not None:
                st.dataframe(msg["df"], use_container_width=True, hide_index=True)
                _auto_chart(msg["df"], msg["content"])
            if msg.get("latency_ms"):
                st.caption(f"⚡ {msg['latency_ms']}ms")

    if question := st.chat_input(placeholder, key=f"{key_prefix}_input"):
        history.append({"role": "user", "content": question})
        with st.spinner("Consultando dados…"):
            result = ask_analyst(question, model_file)

        df = pd.DataFrame()
        if result.get("sql") and not result.get("error"):
            try:
                df = _run_query(result["sql"])
            except Exception as exc:
                st.warning(f"SQL gerado mas falhou ao executar: {exc}")

        if result.get("error"):
            entry = {"role": "assistant", "content": f"❌ {result['error']}"}
        else:
            answer = result.get("text") or (f"{len(df)} resultados encontrados." if not df.empty else "Nenhum resultado.")
            entry = {
                "role": "assistant",
                "content": answer,
                "sql": result.get("sql"),
                "df": df if not df.empty else None,
                "latency_ms": result.get("latency_ms"),
            }

        history.append(entry)
        st.rerun()

    if history:
        if st.button("🗑️ Limpar", key=f"{key_prefix}_clear"):
            st.session_state[history_key] = []
            st.rerun()
