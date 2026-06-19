"""Onboarding wizard — mapeamento de tabelas, org config e credenciais de API."""

import streamlit as st
from utils.auth import get_org_id, get_current_user
from utils.onboarding import (
    get_onboarding_status,
    map_reference_table,
    unmap_reference_table,
    save_api_credential,
    save_user_org_mapping,
    remove_user_org_mapping,
    validate_table_schema,
)

st.set_page_config(page_title="Setup — NEXUS", layout="wide", page_icon="⚙️")
st.title("Configuracao Inicial")
st.caption("Configure suas fontes de dados, organizacao e integrações de API")

org_id = get_org_id()
current_user = get_current_user()
status = get_onboarding_status(org_id)

# ── Status bar ────────────────────────────────────────────────────────────────
mapped_count = sum(1 for v in status["sources"].values() if v)
cols = st.columns(4)
cols[0].metric("Tabelas Mapeadas", f"{mapped_count}/3", delta=None)
cols[1].metric("Usuarios Configurados", len(status["users"]))
cols[2].metric("APIs Conectadas", status["api_count"])
cols[3].metric("Fonte de Dados", "Real" if mapped_count > 0 else "Demo")

if mapped_count == 3 and status["org_configured"]:
    st.success("Setup completo! Suas fontes de dados estao conectadas.")
elif mapped_count == 0:
    st.info(
        "Nenhuma tabela mapeada ainda. O NEXUS esta usando dados de demonstracao. "
        "Mapeie suas tabelas abaixo para usar dados reais."
    )

st.divider()

# ── Passo 1: Mapeamento de tabelas ────────────────────────────────────────────
with st.expander("Passo 1: Conectar suas tabelas Snowflake", expanded=mapped_count < 3):
    st.markdown(
        "Mapeie suas tabelas Snowflake existentes para o NEXUS. "
        "Se nao mapear, os dados de demonstracao serao usados automaticamente."
    )

    REFERENCES = [
        {
            "ref_name": "customer_table",
            "label": "Tabela de Clientes",
            "placeholder": "MINHA_DB.MEU_SCHEMA.CUSTOMERS",
            "required_cols": ["customer_id", "email", "created_at"],
            "help": "Colunas minimas: customer_id, email, created_at",
        },
        {
            "ref_name": "transactions_table",
            "label": "Tabela de Transacoes",
            "placeholder": "BILLING.PUBLIC.INVOICES",
            "required_cols": ["transaction_id", "customer_id", "amount", "created_at"],
            "help": "Colunas minimas: transaction_id, customer_id, amount, created_at",
        },
        {
            "ref_name": "events_table",
            "label": "Tabela de Eventos de Produto",
            "placeholder": "ANALYTICS.EVENTS.USER_EVENTS",
            "required_cols": ["user_id", "event_name", "occurred_at"],
            "help": "Colunas minimas: user_id, event_name, occurred_at",
        },
    ]

    for ref in REFERENCES:
        ref_name = ref["ref_name"]
        is_mapped = status["sources"].get(ref_name, False)

        col_label, col_status = st.columns([3, 1])
        with col_label:
            st.subheader(ref["label"])
        with col_status:
            if is_mapped:
                st.success("Conectada")
            else:
                st.warning("Usando demo")

        if is_mapped:
            if st.button(f"Desconectar {ref['label']}", key=f"unmap_{ref_name}"):
                if unmap_reference_table(ref_name):
                    st.success(f"{ref['label']} desconectada. Usando demo data.")
                    st.rerun()
        else:
            table_input = st.text_input(
                f"Caminho da tabela ({ref['label']})",
                placeholder=ref["placeholder"],
                help=ref["help"],
                key=f"input_{ref_name}",
            )

            col_btn, col_skip = st.columns([2, 1])
            with col_btn:
                if st.button(f"Validar e Conectar", key=f"map_{ref_name}", type="primary"):
                    if not table_input:
                        st.error("Informe o caminho da tabela no formato DATABASE.SCHEMA.TABLE")
                    else:
                        with st.spinner("Validando schema..."):
                            result = validate_table_schema(table_input, ref["required_cols"])
                        if result["valid"]:
                            with st.spinner("Registrando referencia..."):
                                if map_reference_table(ref_name, table_input):
                                    st.success(
                                        f"Conectada com sucesso! {result['row_count']:,} registros encontrados."
                                    )
                                    st.rerun()
                        else:
                            if result["error"]:
                                st.error(result["error"])
                            else:
                                st.error(
                                    f"Colunas faltando: {', '.join(result['missing_columns'])}. "
                                    f"A tabela precisa ter: {', '.join(ref['required_cols'])}"
                                )
            with col_skip:
                st.caption("Ou deixe em branco para usar demo data")

        st.divider()

    st.caption(
        "Nao tem uma tabela compativel? "
        "O NEXUS funciona com qualquer tabela Snowflake — os campos sao mapeados na configuracao."
    )

# ── Passo 2: Configuracao de Organizacao e Usuarios ───────────────────────────
with st.expander("Passo 2: Organizacao e Controle de Acesso", expanded=not status["org_configured"]):
    st.markdown(
        "Configure o isolamento multi-tenant: cada usuario do Snowflake deve ser "
        "mapeado para um `org_id`. Usuarios so verao dados da sua organizacao."
    )

    st.subheader("Org ID atual")
    st.code(org_id)
    st.caption("Para alterar o org_id, edite CONFIG.ORG_USER_MAP diretamente com role NEXUS_ADMIN.")

    st.subheader("Usuarios mapeados")
    if status["users"]:
        for u in status["users"]:
            col_u, col_r, col_del = st.columns([3, 1, 1])
            col_u.write(u["user_name"])
            col_r.write(u.get("role", "analyst"))
            if col_del.button("Remover", key=f"del_{u['user_name']}"):
                if current_user.upper() == u["user_name"].upper():
                    st.error("Voce nao pode remover seu proprio usuario.")
                elif remove_user_org_mapping(u["user_name"], org_id):
                    st.success(f"Usuario {u['user_name']} removido.")
                    st.rerun()
    else:
        st.warning("Nenhum usuario mapeado. Apenas o usuario atual tem acesso.")

    st.subheader("Adicionar usuario")
    col_new_user, col_new_role, col_add = st.columns([3, 1, 1])
    new_user = col_new_user.text_input("Login Snowflake", placeholder="USER@DOMAIN.COM")
    new_role = col_new_role.selectbox("Role", ["analyst", "admin", "readonly"])
    if col_add.button("Adicionar", type="primary"):
        if not new_user:
            st.error("Informe o login do usuario.")
        elif save_user_org_mapping(new_user.upper(), org_id, new_role):
            st.success(f"Usuario {new_user.upper()} adicionado com role {new_role}.")
            st.rerun()

# ── Passo 3: Credenciais de API ───────────────────────────────────────────────
with st.expander("Passo 3: Integracao com APIs Externas (opcional)", expanded=False):
    st.markdown(
        "Configure as credenciais para sincronizacao automatica de dados externos. "
        "As chaves sao armazenadas com seguranca no Snowflake (nunca em logs ou UI)."
    )
    st.info(
        "Requer que o NEXUS External Access Integration esteja habilitado — "
        "aprovado automaticamente durante a instalacao do Marketplace."
    )

    tab_sf, tab_zd, tab_st = st.tabs(["Salesforce", "Zendesk", "Stripe"])

    with tab_sf:
        sf_configured = status["api_count"] > 0
        if sf_configured:
            st.success("Salesforce configurado")
            if st.button("Reconfigurar Salesforce"):
                st.session_state["show_sf_form"] = True
        if not sf_configured or st.session_state.get("show_sf_form", False):
            with st.form("salesforce_form"):
                sf_instance = st.text_input("Instance URL", placeholder="https://mycompany.salesforce.com")
                sf_token = st.text_input("API Token / Session ID", type="password")
                sf_client_id = st.text_input("Connected App Client ID (opcional)")
                if st.form_submit_button("Salvar Salesforce", type="primary"):
                    if sf_instance and sf_token:
                        if save_api_credential(org_id, "salesforce",
                                               {"instance_url": sf_instance, "client_id": sf_client_id}):
                            st.success("Salesforce configurado! Sincronizacao automatica ativada.")
                            st.session_state.pop("show_sf_form", None)
                            st.rerun()
                    else:
                        st.error("Instance URL e Token sao obrigatorios.")

    with tab_zd:
        with st.form("zendesk_form"):
            zd_subdomain = st.text_input("Subdomain", placeholder="minha-empresa")
            zd_email = st.text_input("Email do admin")
            zd_token = st.text_input("API Token", type="password")
            if st.form_submit_button("Salvar Zendesk", type="primary"):
                if zd_subdomain and zd_token:
                    if save_api_credential(org_id, "zendesk",
                                           {"subdomain": zd_subdomain, "email": zd_email}):
                        st.success("Zendesk configurado!")
                        st.rerun()
                else:
                    st.error("Subdomain e Token sao obrigatorios.")

    with tab_st:
        with st.form("stripe_form"):
            st.caption("Use uma Restricted Key com permissao de leitura em Customers e Charges.")
            stripe_key = st.text_input("Stripe API Key (sk_live_... ou rk_live_...)", type="password")
            if st.form_submit_button("Salvar Stripe", type="primary"):
                if stripe_key:
                    if save_api_credential(org_id, "stripe", {}):
                        st.success("Stripe configurado!")
                        st.rerun()
                else:
                    st.error("API Key obrigatoria.")

# ── Acao rapida ───────────────────────────────────────────────────────────────
st.divider()
col_dash, col_reset = st.columns([3, 1])
with col_dash:
    if st.button("Ir para o Dashboard Executivo", type="primary", use_container_width=True):
        st.switch_page("pages/1_Executive_Command.py")
with col_reset:
    if st.button("Resetar para Demo Data", use_container_width=True):
        for ref_name in ["customer_table", "transactions_table", "events_table"]:
            unmap_reference_table(ref_name)
        st.success("Resetado para dados de demonstracao.")
        st.rerun()
