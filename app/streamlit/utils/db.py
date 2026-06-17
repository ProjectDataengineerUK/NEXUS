"""Shared Snowpark session and query helpers."""

import pandas as pd
import streamlit as st
from snowflake.snowpark.context import get_active_session


@st.cache_resource
def get_session():
    return get_active_session()


def run_query(sql: str) -> pd.DataFrame:
    return get_session().sql(sql).to_pandas()


def fmt_usd(value: float, unit: str = "M") -> str:
    if unit == "M":
        return f"${value / 1_000_000:.1f}M"
    if unit == "K":
        return f"${value / 1_000:.0f}K"
    return f"${value:,.0f}"
