"""
NEXUS AI DataOps — Document Intelligence
Sprint 3: upload de documentos, chunking, Cortex Search e chat com documentos.
"""

import json
import uuid

import streamlit as st
from utils.auth import get_org_id
from utils.snowflake_client import cortex_complete as _cortex_complete
from utils.snowflake_client import cortex_search as _cortex_search
from utils.snowflake_client import get_session, run_query, run_sql

st.set_page_config(
    page_title="Document Intelligence · NEXUS",
    page_icon="📄",
    layout="wide",
)

ORG_ID = get_org_id()
SEARCH_SERVICE          = "AI.DOC_SEARCH"
CONTRACT_SEARCH_SERVICE = "AI.CONTRACT_SEARCH"
CHAT_MODEL              = "mistral-large2"

DOC_COLUMNS = ["chunk_text", "document_name", "document_type",
               "document_id", "section_title", "chunk_index"]

CONTRACT_COLUMNS = ["chunk_text", "contract_name", "customer_name",
                    "section_title", "contract_type", "document_id",
                    "contract_value_usd", "end_date", "auto_renewal"]


def cortex_search(query: str, doc_filter: str | None = None, limit: int = 5) -> list[dict]:
    return _cortex_search(query, SEARCH_SERVICE, DOC_COLUMNS, limit, doc_filter)


def contract_search(query: str, limit: int = 5) -> list[dict]:
    return _cortex_search(query, CONTRACT_SEARCH_SERVICE, CONTRACT_COLUMNS, limit)


def cortex_complete(prompt: str) -> str:
    return _cortex_complete(prompt, CHAT_MODEL)


# ─── Sidebar ──────────────────────────────────────────────────────────────────

with st.sidebar:
    st.title("📄 Document Intelligence")
    st.divider()
    tab_choice = st.radio(
        "Navegação",
        ["💬 Chat com Documentos", "📋 Contratos", "📚 Biblioteca", "⬆️ Upload"],
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
        FROM CORE.DOCUMENTS
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
# TAB: Contratos
# ─────────────────────────────────────────────────────────────────────────────

elif tab_choice == "📋 Contratos":
    st.markdown("## 📋 Contract Intelligence")
    st.caption("Busca semântica em contratos, SLAs e aditivos — powered by Cortex Search.")

    col_s1, col_s2 = st.columns([3, 1])
    contract_query = col_s1.text_input(
        "Buscar em contratos",
        placeholder="Ex: cláusula de rescisão, penalidade por SLA, renovação automática…",
    )
    n_results = col_s2.slider("Resultados", 3, 10, 5)

    if contract_query:
        with st.spinner("Buscando em contratos…"):
            results = contract_search(contract_query, limit=n_results)

        if not results:
            st.info("Nenhum trecho relevante encontrado. Faça upload de contratos na aba Upload.")
        else:
            st.success(f"{len(results)} trechos encontrados")
            for i, r in enumerate(results, 1):
                contract_name = r.get("contract_name", "—")
                customer      = r.get("customer_name", "—")
                section       = r.get("section_title", "")
                ctype         = r.get("contract_type", "")
                value         = r.get("contract_value_usd")
                end_dt        = r.get("end_date", "")
                renewal       = r.get("auto_renewal", False)
                text          = r.get("chunk_text", "")

                label = f"**{i}. {contract_name}** — {customer}"
                if ctype:
                    label += f" · _{ctype}_"
                with st.expander(label, expanded=(i == 1)):
                    st.markdown(text)
                    meta = st.columns(3)
                    meta[0].caption(f"Seção: {section or '—'}")
                    meta[1].caption(f"Valor: {'${:,.0f}'.format(value) if value else '—'}")
                    meta[2].caption(f"Vencimento: {end_dt or '—'} {'🔄' if renewal else ''}")

    st.divider()

    # Resumo de contratos próximos do vencimento
    st.subheader("Contratos próximos do vencimento")
    try:
        expiring = run_query(f"""
            SELECT contract_name, customer_name, end_date,
                   contract_value_usd, auto_renewal, days_to_expiry
            FROM AI.V_CONTRACT_INTELLIGENCE
            WHERE org_id = '{ORG_ID}'
              AND renewal_status IN ('EXPIRING_SOON', 'RENEW_WATCH')
            ORDER BY days_to_expiry
            LIMIT 10
        """)
        if expiring.empty:
            st.info("Nenhum contrato expirando nos próximos 90 dias.")
        else:
            st.dataframe(expiring, use_container_width=True, hide_index=True)
    except Exception as e:
        st.caption(f"Tabela V_CONTRACT_INTELLIGENCE ainda não populada: {e}")


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
            d.document_category,
            d.document_summary            AS ai_summary,
            TO_JSON(d.extracted_fields)   AS extracted_fields_json,
            d.created_at
        FROM CORE.DOCUMENTS d
        LEFT JOIN CORE.CUSTOMERS c
            ON d.entity_id = c.customer_id AND c.org_id = d.org_id
        LEFT JOIN AI.DOCUMENT_CHUNKS ch
            ON d.document_id = ch.document_id
        WHERE d.org_id = '{ORG_ID}'
        GROUP BY 1,2,3,4,5,6,8,9,10,11,12
        ORDER BY d.created_at DESC
    """)

    if lib_df.empty:
        st.info("Nenhum documento na biblioteca. Use a aba Upload para adicionar.")
    else:
        # Métricas
        total_docs   = len(lib_df)
        total_chunks = int(lib_df["CHUNKS"].sum())
        done_docs    = int((lib_df["PROCESSING_STATUS"] == "completed").sum())
        pending_docs = int((lib_df["PROCESSING_STATUS"] == "pending").sum())

        m1, m2, m3, m4 = st.columns(4)
        m1.metric("Documentos", total_docs)
        m2.metric("Processados", done_docs)
        m3.metric("Pendentes", pending_docs)
        m4.metric("Chunks pesquisáveis", total_chunks)
        st.divider()

        # Botão de enriquecimento em lote (documentos sem category)
        unenriched = int(((lib_df["DOCUMENT_CATEGORY"].isna()) | (lib_df["DOCUMENT_CATEGORY"] == "")).sum())
        if unenriched > 0:
            if st.button(f"Enriquecer {unenriched} doc(s) com AI_CLASSIFY + AI_SUMMARIZE"):
                with st.spinner("Classificando e resumindo documentos…"):
                    try:
                        result = run_sql(f"CALL CORE.ENRICH_DOCUMENTS_WITH_AI('{ORG_ID}')")
                        msg = result[0][0] if result else "sem retorno"
                        st.success(f"Enriquecimento concluído: {msg}")
                        st.rerun()
                    except Exception as ex:
                        st.error(f"Erro: {ex}")

        # Botão de processamento em lote de pendentes
        if pending_docs > 0:
            if st.button(f"Processar {pending_docs} doc(s) pendente(s)"):
                with st.spinner("Processando documentos pendentes…"):
                    try:
                        result = run_sql(
                            f"CALL AI.SP_PROCESS_PENDING_DOCUMENTS('{ORG_ID}')"
                        )
                        msg = result[0][0] if result else "sem retorno"
                        st.success(f"Processamento concluído: {msg}")
                        st.rerun()
                    except Exception as ex:
                        st.error(f"Erro: {ex}")

        for _, doc in lib_df.iterrows():
            doc_id      = doc["DOCUMENT_ID"]
            doc_status  = doc["PROCESSING_STATUS"]
            status_icon = {"completed": "✅", "pending": "⏳", "processing": "🔄", "failed": "❌"}.get(
                doc_status, "❓"
            )
            category_badge = f" · `{doc['DOCUMENT_CATEGORY']}`" if doc.get("DOCUMENT_CATEGORY") else ""
            with st.expander(
                f"{status_icon} **{doc['DOCUMENT_NAME']}** — `{doc['DOCUMENT_TYPE']}`"
                f"{category_badge} · {doc['CHUNKS']} chunks"
            ):
                col1, col2 = st.columns([3, 1])
                with col1:
                    st.markdown(f"**Cliente/Entidade:** {doc['ENTITY_NAME']}")
                    st.markdown(f"**Tipo de entidade:** {doc['ENTITY_TYPE']}")
                    st.markdown(f"**Status:** {doc_status}")

                    # Sumário: prefere AI_SUMMARY (gerado por CORTEX.SUMMARIZE)
                    ai_summary_val = doc.get("AI_SUMMARY") or ""
                    summary_val    = doc.get("SUMMARY") or ""
                    if ai_summary_val:
                        with st.expander("Sumário executivo (Cortex AI)", expanded=True):
                            st.markdown(f"_{ai_summary_val}_")
                    elif summary_val:
                        with st.expander("Sumário", expanded=True):
                            st.markdown(f"_{summary_val}_")

                    # Campos estruturados extraídos via CORTEX.COMPLETE
                    raw_fields = doc.get("EXTRACTED_FIELDS_JSON") or ""
                    if raw_fields and raw_fields not in ("null", "NULL", ""):
                        try:
                            parsed_fields = json.loads(raw_fields)
                            with st.expander("Campos extraídos (Cortex AI)", expanded=False):
                                st.json(parsed_fields)
                        except (json.JSONDecodeError, TypeError):
                            pass  # VARIANT inválido — não exibe silenciosamente

                with col2:
                    st.caption(f"Criado em: {str(doc['CREATED_AT'])[:10]}")

                    # Botão: processar/re-processar documento individualmente
                    btn_label = (
                        "Processar documento"
                        if doc_status in ("pending", "failed")
                        else "Re-processar"
                    )
                    if st.button(btn_label, key=f"process_{doc_id}"):
                        with st.spinner(f"Processando {doc['DOCUMENT_NAME']}…"):
                            try:
                                result = run_sql(
                                    f"CALL AI.SP_PROCESS_DOCUMENT('{doc_id}', '{ORG_ID}')"
                                )
                                msg = result[0][0] if result else "sem retorno"
                                if msg.startswith("OK"):
                                    st.success(msg)
                                    st.rerun()
                                else:
                                    st.error(f"Falha: {msg}")
                            except Exception as ex:
                                st.error(str(ex))

                    if st.button("Pesquisar neste doc", key=f"lib_search_{doc_id}"):
                        st.session_state["lib_filter_doc"] = doc_id
                        st.info("Selecione 'Chat com Documentos' e filtre por este documento.")

                    # Botão de classificação rápida (sem re-processar tudo)
                    if not doc.get("DOCUMENT_CATEGORY"):
                        if st.button("Classificar", key=f"enrich_{doc_id}"):
                            with st.spinner("Classificando…"):
                                try:
                                    result = run_sql(
                                        f"CALL AI.SP_PROCESS_DOCUMENT('{doc_id}', '{ORG_ID}')"
                                    )
                                    msg = result[0][0] if result else "sem retorno"
                                    if msg.startswith("OK"):
                                        st.success("Classificado.")
                                        st.rerun()
                                    else:
                                        st.error(f"Falha: {msg}")
                                except Exception as ex:
                                    st.error(str(ex))


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
            FROM CORE.CUSTOMERS
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
            INSERT INTO CORE.DOCUMENTS
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
                import os
                import tempfile
                with tempfile.NamedTemporaryFile(delete=False, suffix=".pdf") as tmp:
                    tmp.write(uploaded_file.getbuffer())
                    tmp_path = tmp.name

                session.file.put(
                    tmp_path,
                    f"@CORE.DOC_STAGE/{doc_id}/",
                    auto_compress=False,
                    overwrite=True,
                )
                os.unlink(tmp_path)

                st.write("🧠 Extraindo texto e gerando chunks com Cortex…")
                result = session.sql(f"""
                    CALL CORE.SP_PROCESS_DOCUMENT(
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
