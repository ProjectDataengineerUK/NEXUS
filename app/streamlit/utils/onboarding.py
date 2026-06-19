"""Helpers para o wizard de onboarding — mapeamento de tabelas, credentials e org config."""

from __future__ import annotations

import streamlit as st
from snowflake.snowpark.context import get_active_session


def _session():
    return get_active_session()


@st.cache_data(ttl=30)
def get_onboarding_status(org_id: str) -> dict:
    """Retorna o status atual de onboarding do consumer."""
    sess = _session()

    sources = {
        r["SOURCE_NAME"]: r["IS_ACTIVE"]
        for r in sess.sql("SELECT source_name, is_active FROM CONFIG.DATA_SOURCES").collect()
    }

    users = [
        {"user_name": r["USER_NAME"], "role": r["ROLE"]}
        for r in sess.sql(
            f"SELECT user_name, role FROM CONFIG.ORG_USER_MAP WHERE org_id = '{org_id}'"
        ).collect()
    ]

    api_count = sess.sql(
        "SELECT COUNT(*) AS c FROM CONFIG.APP_SETTINGS WHERE setting_key LIKE 'api_%_configured' AND setting_value = 'true'"
    ).collect()[0]["C"]

    return {
        "tables_mapped": sources.get("customer_table", False),
        "sources": sources,
        "org_configured": bool(users),
        "users": users,
        "api_count": int(api_count),
    }


def validate_table_schema(
    full_table_name: str,
    required_columns: list[str],
) -> dict:
    """Verifica se a tabela existe e tem as colunas mínimas esperadas."""
    sess = _session()
    try:
        parts = full_table_name.strip().upper().split(".")
        if len(parts) != 3:
            return {"valid": False, "missing_columns": [], "row_count": 0,
                    "error": "Use o formato DATABASE.SCHEMA.TABLE"}

        db, schema, table = parts
        cols_result = sess.sql(
            f"SELECT COLUMN_NAME FROM {db}.INFORMATION_SCHEMA.COLUMNS "
            f"WHERE TABLE_SCHEMA = '{schema}' AND TABLE_NAME = '{table}'"
        ).collect()

        existing = {r["COLUMN_NAME"].lower() for r in cols_result}
        missing = [c for c in required_columns if c.lower() not in existing]

        if not existing:
            return {"valid": False, "missing_columns": required_columns, "row_count": 0,
                    "error": f"Tabela {full_table_name} nao encontrada ou sem permissao de acesso"}

        count = sess.sql(f"SELECT COUNT(*) AS c FROM {full_table_name}").collect()[0]["C"]

        return {
            "valid": len(missing) == 0,
            "missing_columns": missing,
            "row_count": int(count),
            "error": None,
        }
    except Exception as exc:
        return {"valid": False, "missing_columns": required_columns, "row_count": 0, "error": str(exc)}


def map_reference_table(ref_name: str, full_table_name: str) -> bool:
    """Registra o mapeamento de referência via CORE.REGISTER_REFERENCE SP."""
    sess = _session()
    try:
        sess.sql(
            f"CALL CORE.REGISTER_REFERENCE('{ref_name}', 'ADD', SYSTEM$REFERENCE('TABLE', '{full_table_name}', 'PERSISTENT', 'SELECT'))"
        ).collect()
        sess.sql(
            f"UPDATE CONFIG.DATA_SOURCES SET is_active = TRUE, mapped_at = CURRENT_TIMESTAMP() WHERE source_name = '{ref_name}'"
        ).collect()
        st.cache_data.clear()
        return True
    except Exception as exc:
        st.error(f"Erro ao mapear {ref_name}: {exc}")
        return False


def unmap_reference_table(ref_name: str) -> bool:
    """Remove o mapeamento de uma referência."""
    sess = _session()
    try:
        sess.sql(f"CALL CORE.REGISTER_REFERENCE('{ref_name}', 'REMOVE', '')").collect()
        sess.sql(
            f"UPDATE CONFIG.DATA_SOURCES SET is_active = FALSE, mapped_at = NULL WHERE source_name = '{ref_name}'"
        ).collect()
        st.cache_data.clear()
        return True
    except Exception as exc:
        st.error(f"Erro ao desregistrar {ref_name}: {exc}")
        return False


def save_user_org_mapping(user_login: str, org_id: str, role: str = "analyst") -> bool:
    """Adiciona ou atualiza o mapeamento user → org_id na CONFIG.ORG_USER_MAP."""
    sess = _session()
    try:
        sess.sql(f"""
            MERGE INTO CONFIG.ORG_USER_MAP t
            USING (SELECT '{user_login}' AS user_name, '{org_id}' AS org_id, '{role}' AS role) s
            ON t.user_name = s.user_name AND t.org_id = s.org_id
            WHEN MATCHED THEN UPDATE SET role = s.role
            WHEN NOT MATCHED THEN INSERT (user_name, org_id, role) VALUES (s.user_name, s.org_id, s.role)
        """).collect()
        st.cache_data.clear()
        return True
    except Exception as exc:
        st.error(f"Erro ao salvar mapeamento: {exc}")
        return False


def remove_user_org_mapping(user_login: str, org_id: str) -> bool:
    sess = _session()
    try:
        sess.sql(f"DELETE FROM CONFIG.ORG_USER_MAP WHERE user_name = '{user_login}' AND org_id = '{org_id}'").collect()
        st.cache_data.clear()
        return True
    except Exception as exc:
        st.error(f"Erro ao remover usuario: {exc}")
        return False


def save_api_credential(org_id: str, provider: str, config: dict) -> bool:
    """Armazena configuração de API em CONFIG.APP_SETTINGS (sem guardar secrets em plain-text)."""
    sess = _session()
    try:
        sess.sql(f"""
            MERGE INTO CONFIG.APP_SETTINGS t
            USING (SELECT 'api_{provider}_configured' AS setting_key, 'true' AS setting_value,
                          'API {provider} configurada para org {org_id}' AS description) s
            ON t.setting_key = s.setting_key
            WHEN MATCHED THEN UPDATE SET setting_value = 'true', updated_at = CURRENT_TIMESTAMP()
            WHEN NOT MATCHED THEN INSERT (setting_key, setting_value, description) VALUES (s.setting_key, s.setting_value, s.description)
        """).collect()

        if "instance_url" in config:
            sess.sql(f"""
                MERGE INTO CONFIG.APP_SETTINGS t
                USING (SELECT 'api_{provider}_instance_url' AS setting_key,
                              '{config["instance_url"]}' AS setting_value, '' AS description) s
                ON t.setting_key = s.setting_key
                WHEN MATCHED THEN UPDATE SET setting_value = s.setting_value
                WHEN NOT MATCHED THEN INSERT (setting_key, setting_value, description) VALUES (s.setting_key, s.setting_value, s.description)
            """).collect()

        if "subdomain" in config:
            sess.sql(f"""
                MERGE INTO CONFIG.APP_SETTINGS t
                USING (SELECT 'api_{provider}_subdomain' AS setting_key,
                              '{config["subdomain"]}' AS setting_value, '' AS description) s
                ON t.setting_key = s.setting_key
                WHEN MATCHED THEN UPDATE SET setting_value = s.setting_value
                WHEN NOT MATCHED THEN INSERT (setting_key, setting_value, description) VALUES (s.setting_key, s.setting_value, s.description)
            """).collect()

        st.cache_data.clear()
        return True
    except Exception as exc:
        st.error(f"Erro ao salvar credencial {provider}: {exc}")
        return False
