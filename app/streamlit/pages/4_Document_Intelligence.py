"""
NEXUS AI DataOps — Document Intelligence
Sprint 3: upload de documentos, chunking, Cortex Search e chat com documentos.
"""

import json
import uuid
import streamlit as st
import pandas as pd
from snowflake.snowpark.context import get_active_session

st.set_page_config(
    page_title="Document Intelligence · NEXUS",
    page_icon="📄",
    layout="wide",
)

ORG_ID = "ORG-DEMO-001"
SEARCH_SERVICE = "NEXUS_APP.AI.DOC_SEARCH"
CHAT_MODEL = "mistral-large2"


@st.cache_resource
def get_session():
    return get_active_session()


def run_query(sql: str) -> pd.DataFrame:
    return get_session().sql(sql).to_pandas()


def cortex_search(query: str, doc_filter: str | None = None, limit: int = 5) -> list[dict]:
    """Executa busca semântica via Cortex Search REST API."""
    session = get_session()

    filter_clause = ""
    if doc_filter:
        filter_clause = f', "filter": {{"@eq": {{"document_id": "{doc_filter}"}}}}'

    search_sql = f"""
        SELECT PARSE_JSON(
            SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
                '{SEARCH_SERVICE}',
                '{{
                    "query":   "{query.replace('"', '').replace("'", "")}",
                    "columns": ["chunk_text","document_name","document_type",
                                "document_id","section_title","chunk_index"],
                    "limit":   {limit}
                    {filter_clause}
                }}'
            )
        ) AS results
    """
    rows = session.sql(search_sql).collect()
    if not rows:
        return []
    raw = rows[0]["RESULTS"]
    if isinstance(raw, str):
        raw = json.loads(raw)
    return raw.get("results", [])


def cortex_complete(prompt: str) -> str:
    """Chama Cortex Complete e retorna o texto gerado."""
    safe = prompt.replace("'", "\\'").replace("\\n", " ")
    sql = f"SELECT SNOWFLAKE.CORTEX.COMPLETE('{CHAT_MODEL}', '{safe}') AS answer"
    rows = get_session().sql(sql).collect()
    return rows[0]["ANSWER"] if rows else ""


# ─── Sidebar ──────────────────────────────────────────────────────────────────

with st.sidebar:
    st.title("📄 Document Intelligence")
    st.divider()
    tab_choice = st.radio(
        "Navegação",
        ["💬 Chat com Documentos", "📚 Biblioteca", "⬆️ Upload"],
    )
    st.divider()
    st.caption(f"Modelo de chat: `{CHAT_MODEL}`")
    st.caption("Busca semântica: Cortex Search")
    st.page_link("Home.py", label="← Voltar ao Home", icon="⚡")


# ─────────────────────────────────────────────────────────────────────────────
# TAB: Chat com Documentos
# ─────────────────────────────────────────────────────────────────────────────

if tab_choice == "💬 Chat com Documentos":
    st.markdown("## 💬 Chat com Documentos")
    st.caption("Faça perguntas em linguagem natural sobre contratos, SLAs e relatórios.")

    # Filtro de documento (opcional)
    docs_df = run_query(f"""
        SELECT document_id, document_name, document_type
        FROM NEXUS_APP.CORE.DOCUMENTS
        WHERE org_id = '{ORG_ID}' AND processing_status = 'completed'
        ORDER BY document_name
    """)

    doc_options = {"Todos os documentos": None}
    for _, d in docs_df.iterrows():
        doc_options[f"{d['DOCUMENT_NAME']} ({d['DOCUMENT_TYPE']})"] = d["DOCUMENT_ID"]

    selected_doc_label = st.selectbox("Filtrar por documento (opcional)", list(doc_options.keys()))
    selected_doc_id = doc_options[selected_doc_label]

    st.divider()

    # Histórico de chat na sessão
    if "doc_chat_history" not in st.session_state:
        st.session_state.doc_chat_history = []

    # Sugestões de perguntas
    suggestions = [
        "Qual é a multa por rescisão antecipada do contrato Acme?",
        "Quais são os tempos de resposta para incidentes P1?",
        "Como funciona a renovação automática?",
        "O que acontece se a integração Salesforce falhar?",
    ]

    with st.expander("💡 Perguntas sugeridas", expanded=len(st.session_state.doc_chat_history) == 0):
        cols = st.columns(2)
        for i, sug in enumerate(suggestions):
            if cols[i % 2].button(sug, key=f"sug_{i}"):
                st.session_state.doc_chat_history.append({"role": "user", "content": sug})
                st.rerun()

    # Renderiza histórico
    for msg in st.session_state.doc_chat_history:
        with st.chat_message(msg["role"]):
            st.markdown(msg["content"])
            if msg.get("sources"):
                with st.expander(f"📎 {len(msg['sources'])} fonte(s) usadas"):
                    for src in msg["sources"]:
                        st.markdown(f"**{src['document_name']}** · {src.get('section_title','—')}")
                        st.caption(src["chunk_text"][:300] + "…")

    # Input do usuário
    if question := st.chat_input("Pergunte sobre um documento…"):
        st.session_state.doc_chat_history.append({"role": "user", "content": question})

        with st.chat_message("user"):
            st.markdown(question)

        with st.chat_message("assistant"):
            with st.spinner("Buscando contexto e gerando resposta…"):

                # 1. Cortex Search — recupera chunks relevantes
                chunks = cortex_search(question, doc_filter=selected_doc_id, limit=4)

                if not chunks:
                    answer = "Não encontrei informações relevantes nos documentos disponíveis. Tente reformular a pergunta ou faça upload de mais documentos."
                    sources = []
                else:
                    # 2. Monta contexto para o LLM
                    context_parts = []
                    for i, c in enumerate(chunks, 1):
                        doc_name = c.get("document_name", "Documento")
                        section  = c.get("section_title", "")
                        text     = c.get("chunk_text", "")
                        context_parts.append(f"[Fonte {i} — {doc_name} / {section}]\n{text}")

                    context_text = "\n\n---\n\n".join(context_parts)

                    prompt = (
                        "Você é o assistente jurídico e corporativo da NEXUS AI DataOps. "
                        "Responda a pergunta abaixo com base EXCLUSIVAMENTE no contexto fornecido. "
                        "Seja preciso, cite os documentos quando relevante, e avise se a informação não estiver disponível no contexto.\n\n"
                        f"CONTEXTO:\n{context_text}\n\n"
                        f"PERGUNTA: {question}\n\n"
                        "RESPOSTA:"
                    )

                    answer = cortex_complete(prompt)
                    sources = chunks

                st.markdown(answer)

                if sources:
                    with st.expander(f"📎 {len(sources)} fonte(s) usadas"):
                        for src in sources:
                            st.markdown(f"**{src.get('document_name','—')}** · {src.get('section_title','—')}")
                            st.caption(src.get("chunk_text","")[:300] + "…")

        st.session_state.doc_chat_history.append({
            "role": "assistant",
            "content": answer,
            "sources": sources if chunks else [],
        })

    if st.session_state.doc_chat_history:
        if st.button("🗑️ Limpar conversa"):
            st.session_state.doc_chat_history = []
            st.rerun()


# ─────────────────────────────────────────────────────────────────────────────
# TAB: Biblioteca
# ─────────────────────────────────────────────────────────────────────────────

elif tab_choice == "📚 Biblioteca":
    st.markdown("## 📚 Biblioteca de Documentos")

    lib_df = run_query(f"""
        SELECT
            d.document_id,
            d.document_name,
            d.document_type,
            d.entity_type,
            COALESCE(c.name, d.entity_id) AS entity_name,
            d.processing_status,
            COUNT(ch.chunk_id)            AS chunks,
            d.summary,
            d.created_at
        FROM NEXUS_APP.CORE.DOCUMENTS d
        LEFT JOIN NEXUS_APP.CORE.CUSTOMERS c
            ON d.entity_id = c.customer_id AND c.org_id = d.org_id
        LEFT JOIN NEXUS_APP.AI.DOCUMENT_CHUNKS ch
            ON d.document_id = ch.document_id
        WHERE d.org_id = '{ORG_ID}'
        GROUP BY 1,2,3,4,5,6,8,9
        ORDER BY d.created_at DESC
    """)

    if lib_df.empty:
        st.info("Nenhum documento na biblioteca. Use a aba Upload para adicionar.")
    else:
        # Métricas
        total_docs   = len(lib_df)
        total_chunks = int(lib_df["CHUNKS"].sum())
        done_docs    = int((lib_df["PROCESSING_STATUS"] == "completed").sum())

        m1, m2, m3 = st.columns(3)
        m1.metric("Documentos", total_docs)
        m2.metric("Indexados", done_docs)
        m3.metric("Chunks pesquisáveis", total_chunks)
        st.divider()

        for _, doc in lib_df.iterrows():
            status_icon = {"completed": "✅", "pending": "⏳", "failed": "❌"}.get(
                doc["PROCESSING_STATUS"], "❓"
            )
            with st.expander(
                f"{status_icon} **{doc['DOCUMENT_NAME']}** — `{doc['DOCUMENT_TYPE']}` "
                f"· {doc['CHUNKS']} chunks"
            ):
                col1, col2 = st.columns([3, 1])
                with col1:
                    st.markdown(f"**Cliente/Entidade:** {doc['ENTITY_NAME']}")
                    st.markdown(f"**Tipo de entidade:** {doc['ENTITY_TYPE']}")
                    st.markdown(f"**Status:** {doc['PROCESSING_STATUS']}")
                    if doc["SUMMARY"]:
                        st.markdown(f"**Sumário:**  \n_{doc['SUMMARY']}_")
                with col2:
                    st.caption(f"Criado em: {str(doc['CREATED_AT'])[:10]}")
                    if st.button("🔍 Pesquisar neste doc", key=f"lib_search_{doc['DOCUMENT_ID']}"):
                        st.session_state["lib_filter_doc"] = doc["DOCUMENT_ID"]
                        st.info("Selecione 'Chat com Documentos' e filtre por este documento.")


# ─────────────────────────────────────────────────────────────────────────────
# TAB: Upload
# ─────────────────────────────────────────────────────────────────────────────

elif tab_choice == "⬆️ Upload":
    st.markdown("## ⬆️ Upload de Documento")
    st.caption("Faça upload de PDFs, contratos e relatórios para indexação automática.")

    with st.form("upload_form"):
        uploaded_file = st.file_uploader(
            "Selecione um arquivo PDF",
            type=["pdf"],
            help="Máximo 50 MB. PDFs com texto extraível têm melhor qualidade.",
        )

        col_a, col_b = st.columns(2)
        with col_a:
            doc_type = st.selectbox(
                "Tipo de documento",
                ["contract", "sla", "report", "proposal", "manual", "policy", "other"],
            )
        with col_b:
            entity_type = st.selectbox("Associar a", ["customer", "product", "org"])

        # Busca entidades disponíveis para associação
        customers_df = run_query(f"""
            SELECT customer_id AS id, name AS label
            FROM NEXUS_APP.CORE.CUSTOMERS
            WHERE org_id = '{ORG_ID}'
            ORDER BY name
        """)
        entity_options = {"(sem associação)": None}
        for _, e in customers_df.iterrows():
            entity_options[e["LABEL"]] = e["ID"]

        entity_label = st.selectbox("Cliente/Entidade (opcional)", list(entity_options.keys()))
        entity_id = entity_options[entity_label] or ""

        submitted = st.form_submit_button("📤 Processar documento", type="primary")

    if submitted and uploaded_file:
        session = get_session()
        doc_id    = f"DOC-{str(uuid.uuid4())[:8].upper()}"
        doc_name  = uploaded_file.name
        stage_path = f"{doc_id}/{doc_name}"

        # Registra como pendente
        session.sql(f"""
            INSERT INTO NEXUS_APP.CORE.DOCUMENTS
                (document_id, org_id, entity_id, entity_type, document_name,
                 document_type, stage_path, processing_status)
            VALUES
                ('{doc_id}', '{ORG_ID}', '{entity_id}', '{entity_type}',
                 '{doc_name.replace("'","")}', '{doc_type}',
                 '{stage_path}', 'pending')
        """).collect()

        with st.status("Processando documento…", expanded=True) as status:
            st.write("📤 Fazendo upload para o stage…")
            try:
                # Upload para stage interno Snowflake
                import tempfile, os
                with tempfile.NamedTemporaryFile(delete=False, suffix=".pdf") as tmp:
                    tmp.write(uploaded_file.getbuffer())
                    tmp_path = tmp.name

                session.file.put(
                    tmp_path,
                    f"@NEXUS_APP.CORE.DOC_STAGE/{doc_id}/",
                    auto_compress=False,
                    overwrite=True,
                )
                os.unlink(tmp_path)

                st.write("🧠 Extraindo texto e gerando chunks com Cortex…")
                result = session.sql(f"""
                    CALL NEXUS_APP.CORE.SP_PROCESS_DOCUMENT(
                        '{doc_id}', '{ORG_ID}', '{stage_path}',
                        '{doc_name.replace("'","")}', '{doc_type}',
                        '{entity_id}', '{entity_type}'
                    )
                """).collect()

                msg = result[0][0] if result else "ERROR: sem retorno"

                if msg.startswith("OK"):
                    st.write(f"✅ {msg}")
                    status.update(label="Documento processado com sucesso!", state="complete")
                    st.success(f"**{doc_name}** indexado com sucesso. ID: `{doc_id}`")
                    st.info("Acesse 'Chat com Documentos' para fazer perguntas.")
                else:
                    status.update(label="Falha no processamento", state="error")
                    st.error(f"Erro ao processar: {msg}")

            except Exception as e:
                status.update(label="Erro no upload", state="error")
                st.error(f"Erro: {str(e)}")

    elif submitted and not uploaded_file:
        st.warning("Selecione um arquivo PDF para continuar.")
