"""
NEXUS AI DataOps — Admin Panel
Sprint 6: RBAC, masking policies, audit log, configurações do app.
"""

import pandas as pd
import streamlit as st
from utils.auth import get_org_id
from utils.snowflake_client import get_session
from utils.snowflake_client import run_query as run_sql

st.set_page_config(
    page_title="Admin · NEXUS",
    page_icon="⚙️",
    layout="wide",
)

ORG_ID = get_org_id()


def execute(sql: str):
    try:
        get_session().sql(sql).collect()
        return True, "OK"
    except Exception as e:
        return False, str(e)


# ─── Sidebar ──────────────────────────────────────────────────────────────────

with st.sidebar:
    st.title("⚙️ Admin")
    st.divider()
    admin_tab = st.radio("Seção", [
        "🔐 RBAC",
        "🎭 Masking Policies",
        "📋 Audit Log",
        "⚙️ Configurações",
    ])
    st.divider()
    st.caption("Acesso restrito a NEXUS_ADMIN.")
    st.page_link("Home.py", label="← Home", icon="⚡")
    st.page_link("pages/6_Data_Quality.py", label="✅ Data Quality")


st.markdown("## ⚙️ Admin Panel")
st.caption("Gerenciamento de RBAC, governança de dados, auditoria e configurações da plataforma.")
st.divider()


# ═════════════════════════════════════════════════════════════════════════════
# RBAC
# ═════════════════════════════════════════════════════════════════════════════

if admin_tab == "🔐 RBAC":
    st.markdown("### 🔐 Controle de Acesso (RBAC)")
    st.caption("Hierarquia de roles NEXUS e mapeamento de usuários por organização.")

    # Hierarquia de roles — estática (documentada no 03_roles.sql)
    st.markdown("#### Hierarquia de Roles")

    hierarchy_data = {
        "Role": [
            "NEXUS_VIEWER",
            "NEXUS_ANALYST",
            "NEXUS_DATA_ENGINEER",
            "NEXUS_ADMIN",
        ],
        "Herdado de": [
            "—",
            "NEXUS_VIEWER",
            "NEXUS_VIEWER",
            "NEXUS_ANALYST",
        ],
        "Permissões-chave": [
            "SELECT em MART, AI (dados não-PII). Leitura de dashboards.",
            "NEXUS_VIEWER + SELECT em CORE. Cortex Analyst. INSERT em AUDIT.",
            "NEXUS_VIEWER + CREATE STAGE, PIPE. Ingestão e pipelines.",
            "NEXUS_ANALYST + DDL em CORE/AI. Manage Tasks. Exec SPs.",
        ],
        "Uso típico": [
            "Executivos, stakeholders de negócio",
            "Analistas, CS Managers",
            "Engenheiros de dados",
            "Administradores da plataforma",
        ],
    }
    st.dataframe(pd.DataFrame(hierarchy_data), hide_index=True, use_container_width=True)

    st.divider()

    # Mapeamento org → usuário
    st.markdown("#### Mapeamento Organização → Usuário")
    st.caption("Tabela `CONFIG.ORG_USER_MAP` — usada pelo Row Access Policy para isolamento multi-tenant.")

    org_map_df = run_sql("""
        SELECT org_id, user_name, created_at
        FROM CONFIG.ORG_USER_MAP
        ORDER BY org_id, user_name
    """)

    if org_map_df.empty:
        st.info("Nenhum mapeamento configurado. Adicione usuários abaixo.")
    else:
        st.dataframe(org_map_df, hide_index=True, use_container_width=True)

    st.divider()
    st.markdown("#### Adicionar Mapeamento")
    with st.form("add_rbac_mapping"):
        col1, col2 = st.columns(2)
        new_org  = col1.text_input("Org ID",   value=ORG_ID)
        new_user = col2.text_input("Username", placeholder="ex: john.doe@empresa.com")
        submitted = st.form_submit_button("➕ Adicionar", type="primary")

    if submitted and new_user.strip():
        ok, msg = execute(f"""
            INSERT INTO CONFIG.ORG_USER_MAP (org_id, user_name)
            VALUES ('{new_org}', '{new_user.strip()}')
        """)
        if ok:
            st.success(f"Usuário `{new_user}` mapeado para `{new_org}`.")
            st.rerun()
        else:
            st.error(f"Erro: {msg}")

    # Roles por usuário via Account Usage (somente se permitido)
    st.divider()
    st.markdown("#### Roles Concedidas (Account Usage)")

    try:
        grants_df = run_sql("""
            SELECT
                grantee_name  AS usuario,
                role           AS role_concedida,
                granted_by,
                created_on
            FROM SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_USERS
            WHERE role LIKE 'NEXUS%'
              AND deleted_on IS NULL
            ORDER BY grantee_name, role
            LIMIT 50
        """)
        if grants_df.empty:
            st.info("Nenhuma role NEXUS concedida a usuários ainda.")
        else:
            st.dataframe(grants_df, hide_index=True, use_container_width=True)
    except Exception:
        st.caption("_Account Usage requer privilégio SNOWFLAKE database role. Exibindo roles conhecidas:_")
        st.code("""
-- Conceder role a usuário:
GRANT ROLE NEXUS_ANALYST TO USER "john.doe@empresa.com";

-- Verificar roles do usuário atual:
SHOW GRANTS TO USER CURRENT_USER();
        """, language="sql")


# ═════════════════════════════════════════════════════════════════════════════
# MASKING POLICIES
# ═════════════════════════════════════════════════════════════════════════════

elif admin_tab == "🎭 Masking Policies":
    st.markdown("### 🎭 Masking Policies — Governança de PII")

    # Políticas definidas
    policies = [
        {
            "Nome": "MASK_EMAIL",
            "Schema": "GOVERNANCE",
            "Tipo": "VARCHAR",
            "Lógica": "Oculta domínio: `user@***` para não-analistas",
            "Aplicada em": "CORE.CUSTOMERS.email, CORE.CONTACTS.email",
            "Roles com acesso": "NEXUS_ANALYST, NEXUS_ADMIN",
        },
        {
            "Nome": "MASK_PHONE",
            "Schema": "GOVERNANCE",
            "Tipo": "VARCHAR",
            "Lógica": "Exibe somente últimos 4 dígitos: `****4321`",
            "Aplicada em": "CORE.CUSTOMERS.phone",
            "Roles com acesso": "NEXUS_ANALYST, NEXUS_ADMIN",
        },
        {
            "Nome": "MASK_PII_STRING",
            "Schema": "GOVERNANCE",
            "Tipo": "VARCHAR",
            "Lógica": "Retorna `***MASKED***` para viewers",
            "Aplicada em": "CORE.CONTACTS.address, name em contextos PII",
            "Roles com acesso": "NEXUS_ANALYST, NEXUS_ADMIN",
        },
        {
            "Nome": "MASK_DECIMAL_PII",
            "Schema": "GOVERNANCE",
            "Tipo": "NUMBER",
            "Lógica": "Retorna `NULL` para viewers",
            "Aplicada em": "CORE.TRANSACTIONS.amount (contextos PII)",
            "Roles com acesso": "NEXUS_ANALYST, NEXUS_ADMIN",
        },
    ]

    st.dataframe(pd.DataFrame(policies), hide_index=True, use_container_width=True)

    st.divider()

    # Row Access Policy
    st.markdown("#### Row Access Policy — Isolamento Multi-tenant")
    st.markdown("""
    **`GOVERNANCE.RAP_ORG_ISOLATION`** — aplicada em todas as tabelas de `CORE.*`

    ```sql
    CREATE ROW ACCESS POLICY GOVERNANCE.RAP_ORG_ISOLATION
        AS (record_org_id VARCHAR) RETURNS BOOLEAN ->
        IS_ROLE_IN_SESSION('NEXUS_ADMIN')
        OR EXISTS (
            SELECT 1 FROM CONFIG.ORG_USER_MAP
            WHERE org_id    = record_org_id
              AND user_name = CURRENT_USER()
        );
    ```

    Cada usuário só enxerga linhas cuja `org_id` corresponde ao seu registro em `CONFIG.ORG_USER_MAP`.
    NEXUS_ADMIN tem acesso irrestrito.
    """)

    st.divider()

    # Verificar masking via Information Schema
    try:
        applied_df = run_sql("""
            SELECT
                REF_SCHEMA_NAME   AS schema,
                REF_ENTITY_NAME   AS tabela,
                REF_COLUMN_NAME   AS coluna,
                POLICY_NAME       AS policy
            FROM TABLE(INFORMATION_SCHEMA.POLICY_REFERENCES(
                POLICY_NAME => 'GOVERNANCE.MASK_EMAIL'
            ))
        """)
        if not applied_df.empty:
            st.markdown("#### Aplicações de `MASK_EMAIL` detectadas")
            st.dataframe(applied_df, hide_index=True, use_container_width=True)
    except Exception:
        st.caption("_Para verificar aplicação das policies, execute no Snowflake:_")
        st.code("""
SELECT * FROM TABLE(INFORMATION_SCHEMA.POLICY_REFERENCES(
    POLICY_NAME => 'GOVERNANCE.MASK_EMAIL'
));
        """, language="sql")


# ═════════════════════════════════════════════════════════════════════════════
# AUDIT LOG
# ═════════════════════════════════════════════════════════════════════════════

elif admin_tab == "📋 Audit Log":
    st.markdown("### 📋 Audit Log")

    log_type = st.radio("Tipo de log", [
        "🤖 Cortex Analyst",
        "🎬 Ações",
        "🔑 Acesso",
        "💬 Agent Chat",
    ], horizontal=True)

    days_back = st.slider("Dias atrás", 1, 30, 7)

    if log_type == "🤖 Cortex Analyst":
        df = run_sql(f"""
            SELECT
                created_at,
                user_name,
                user_role,
                question,
                LEFT(generated_sql, 200) AS sql_preview,
                model_used,
                latency_ms,
                was_helpful,
                session_id
            FROM AUDIT.CORTEX_ANALYST_LOG
            WHERE org_id = '{ORG_ID}'
              AND created_at >= DATEADD('day', -{days_back}, CURRENT_TIMESTAMP())
            ORDER BY created_at DESC
            LIMIT 200
        """)
        if df.empty:
            st.info("Sem logs de Cortex Analyst no período.")
        else:
            m1, m2, m3 = st.columns(3)
            m1.metric("Perguntas",        len(df))
            m2.metric("Latência média",   f"{df['LATENCY_MS'].mean():.0f}ms")
            m3.metric("Sessões únicas",   df["SESSION_ID"].nunique())
            st.dataframe(df, hide_index=True, use_container_width=True)

    elif log_type == "🎬 Ações":
        df = run_sql(f"""
            SELECT
                created_at,
                user_name,
                role_name,
                action_type,
                object_type,
                object_id,
                details
            FROM AUDIT.ACTION_LOG
            WHERE org_id = '{ORG_ID}'
              AND created_at >= DATEADD('day', -{days_back}, CURRENT_TIMESTAMP())
            ORDER BY created_at DESC
            LIMIT 200
        """)
        if df.empty:
            st.info("Sem logs de ações no período.")
        else:
            st.metric("Ações registradas", len(df))
            st.dataframe(df, hide_index=True, use_container_width=True)

    elif log_type == "🔑 Acesso":
        df = run_sql(f"""
            SELECT
                created_at,
                user_name,
                role_name,
                resource_type,
                resource_name,
                action,
                success,
                ip_address
            FROM AUDIT.ACCESS_LOG
            WHERE org_id = '{ORG_ID}'
              AND created_at >= DATEADD('day', -{days_back}, CURRENT_TIMESTAMP())
            ORDER BY created_at DESC
            LIMIT 200
        """)
        if df.empty:
            st.info("Sem logs de acesso no período.")
        else:
            denied = int((~df["SUCCESS"]).sum())
            m1, m2 = st.columns(2)
            m1.metric("Acessos registrados", len(df))
            m2.metric("Acessos negados",     denied,
                      delta="⚠️ verificar" if denied > 0 else None,
                      delta_color="inverse")
            st.dataframe(df, hide_index=True, use_container_width=True)

    else:  # Agent Chat
        df = run_sql(f"""
            SELECT
                created_at,
                session_id,
                user_name,
                role,
                LEFT(content, 200) AS content_preview,
                tool_name,
                model_used,
                latency_ms
            FROM AUDIT.AGENT_CHAT_LOG
            WHERE org_id = '{ORG_ID}'
              AND created_at >= DATEADD('day', -{days_back}, CURRENT_TIMESTAMP())
            ORDER BY created_at DESC
            LIMIT 200
        """)
        if df.empty:
            st.info("Sem logs de Agent Chat no período.")
        else:
            m1, m2, m3 = st.columns(3)
            m1.metric("Mensagens",       len(df))
            m2.metric("Sessões",         df["SESSION_ID"].nunique())
            m3.metric("Ferramentas usadas", df["TOOL_NAME"].notna().sum())
            st.dataframe(df, hide_index=True, use_container_width=True)

    if "df" in dir() and not df.empty:
        st.download_button(
            "⬇️ Exportar log",
            df.to_csv(index=False).encode(),
            file_name=f"nexus_audit_{log_type.split()[1].lower()}.csv",
            mime="text/csv",
        )


# ═════════════════════════════════════════════════════════════════════════════
# CONFIGURAÇÕES
# ═════════════════════════════════════════════════════════════════════════════

else:
    st.markdown("### ⚙️ Configurações do App")

    settings_df = run_sql("""
        SELECT setting_key, setting_value, description, updated_at
        FROM CONFIG.APP_SETTINGS
        ORDER BY setting_key
    """)

    if settings_df.empty:
        st.warning("Tabela CONFIG.APP_SETTINGS vazia.")
    else:
        st.caption("Edite os valores abaixo e clique em Salvar para atualizar.")

        # Renderiza campos editáveis
        updated_values = {}
        for _, row in settings_df.iterrows():
            col1, col2 = st.columns([2, 3])
            col1.markdown(f"**`{row['SETTING_KEY']}`**  \n<small>{row['DESCRIPTION'] or ''}</small>",
                          unsafe_allow_html=True)
            new_val = col2.text_input(
                label=row["SETTING_KEY"],
                value=row["SETTING_VALUE"],
                label_visibility="collapsed",
                key=f"setting_{row['SETTING_KEY']}",
            )
            if new_val != row["SETTING_VALUE"]:
                updated_values[row["SETTING_KEY"]] = new_val

        if updated_values:
            st.warning(f"{len(updated_values)} configuração(ões) alterada(s). Clique em Salvar.")

        if st.button("💾 Salvar alterações", type="primary", disabled=not updated_values):
            errors = []
            for key, val in updated_values.items():
                ok, msg = execute(f"""
                    UPDATE CONFIG.APP_SETTINGS
                    SET setting_value = '{val.replace("'","''")}',
                        updated_at    = CURRENT_TIMESTAMP()
                    WHERE setting_key = '{key}'
                """)
                if not ok:
                    errors.append(f"{key}: {msg}")
            if errors:
                st.error("Erros: " + "; ".join(errors))
            else:
                st.success(f"{len(updated_values)} configuração(ões) salva(s).")
                st.rerun()

    st.divider()
    st.markdown("#### 🚀 Informações da Plataforma")

    try:
        version_df = run_sql("SELECT CURRENT_VERSION() AS sf_version, CURRENT_ACCOUNT() AS account, CURRENT_USER() AS usr, CURRENT_ROLE() AS role")
        if not version_df.empty:
            v = version_df.iloc[0]
            col1, col2, col3, col4 = st.columns(4)
            col1.metric("Snowflake Version", v["SF_VERSION"])
            col2.metric("Account",           v["ACCOUNT"])
            col3.metric("User",              v["USR"])
            col4.metric("Role atual",        v["ROLE"])
    except Exception as e:
        st.caption(f"Erro ao consultar metadados: {e}")

    st.divider()
    st.markdown("#### 📦 Native App — Versão")
    st.markdown("""
    | Campo | Valor |
    |---|---|
    | **Nome** | `NEXUS_AI_DATAOPS` |
    | **Versão** | `1.0.0` |
    | **Patch** | `0` |
    | **Distribution** | `EXTERNAL` (Marketplace) |
    | **Setup Script** | `snowflake/native_app/setup_script.sql` |
    | **Manifest** | `snowflake/native_app/manifest.yml` |
    """)

    with st.expander("📄 Instruções de empacotamento Native App"):
        st.code("""
-- 1. Criar Application Package
CREATE APPLICATION PACKAGE IF NOT EXISTS NEXUS_AI_DATAOPS_PKG;

-- 2. Criar stage no package
CREATE STAGE IF NOT EXISTS NEXUS_AI_DATAOPS_PKG.PUBLIC.APP_STAGE;

-- 3. Upload dos arquivos
-- snowsql -c nexus_prod -q "PUT file://snowflake/native_app/manifest.yml @NEXUS_AI_DATAOPS_PKG.PUBLIC.APP_STAGE/v1/ OVERWRITE=TRUE AUTO_COMPRESS=FALSE"
-- snowsql -c nexus_prod -q "PUT file://snowflake/native_app/setup_script.sql @NEXUS_AI_DATAOPS_PKG.PUBLIC.APP_STAGE/v1/ OVERWRITE=TRUE AUTO_COMPRESS=FALSE"

-- 4. Criar versão
ALTER APPLICATION PACKAGE NEXUS_AI_DATAOPS_PKG
    ADD VERSION v1_0 USING @NEXUS_AI_DATAOPS_PKG.PUBLIC.APP_STAGE/v1/;

-- 5. Publicar no Marketplace (via Snowsight → Data Products → Provider Studio)
        """, language="sql")
