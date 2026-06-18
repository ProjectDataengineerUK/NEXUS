"""
NEXUS AI DataOps — Churn Prediction Model (Sprint 5)
Snowpark ML LogisticRegression treinado sobre MART.CUSTOMER_360.
Executado como Stored Procedure; escreve resultados em AI.CHURN_SCORES.
"""

import json

from snowflake.ml.modeling.linear_model import LogisticRegression
from snowflake.ml.modeling.pipeline import Pipeline
from snowflake.ml.modeling.preprocessing import StandardScaler
from snowflake.snowpark import Session
from snowflake.snowpark.functions import col, lit, when

ORG_ID        = "ORG-DEMO-001"
MODEL_VERSION = "1.0.0-lr"

FEATURE_COLS = [
    "HEALTH_SCORE",
    "NPS_SCORE",
    "CHURN_PROBABILITY",       # heuristic score — feature para o modelo ML
    "EVENTS_30D",
    "ACTIVE_DAYS_30D",
    "DAYS_SINCE_LAST_ACTIVITY",
    "OPEN_TICKETS",
    "SLA_BREACHES",
    "MRR",
]

LABEL_COL   = "IS_CHURNED"
PREDICT_COL = "ML_CHURN_PROBABILITY"


def _risk_level(prob: float) -> str:
    if prob >= 0.65:
        return "HIGH"
    elif prob >= 0.35:
        return "MEDIUM"
    return "LOW"


def _top_drivers(row: dict) -> list[str]:
    """Heurística para identificar os top drivers de churn do cliente."""
    drivers = []

    if row.get("HEALTH_SCORE", 100) < 40:
        drivers.append("health_score_crítico")
    if row.get("NPS_SCORE", 0) < -20:
        drivers.append("nps_muito_baixo")
    if row.get("ACTIVE_DAYS_30D", 30) < 5:
        drivers.append("baixo_engajamento")
    if row.get("DAYS_SINCE_LAST_ACTIVITY", 0) > 14:
        drivers.append("inatividade_prolongada")
    if row.get("SLA_BREACHES", 0) > 2:
        drivers.append("multiplas_violacoes_sla")
    if row.get("OPEN_TICKETS", 0) > 3:
        drivers.append("acumulo_de_tickets")
    if row.get("MRR", 1) < 100:
        drivers.append("baixo_mrr")

    return drivers[:3] if drivers else ["perfil_de_risco_moderado"]


def _recommended_action(risk: str, drivers: list[str]) -> str:
    if risk == "HIGH":
        if "baixo_engajamento" in drivers or "inatividade_prolongada" in drivers:
            return "Agendar QBR urgente e oferecer onboarding adicional"
        if "multiplas_violacoes_sla" in drivers:
            return "Escalar para time de CS sênior e revisar SLA"
        return "Contato imediato do CSM + oferta de desconto de retenção"
    elif risk == "MEDIUM":
        if "nps_muito_baixo" in drivers:
            return "Realizar NPS follow-up e coletar feedback detalhado"
        return "Aumentar cadência de contato e revisar health score mensalmente"
    return "Manter cadência padrão e monitorar próxima renovação"


def train_and_score(session: Session) -> str:
    """
    Treina LogisticRegression sobre dados históricos (lifecycle = churned = 1),
    prediz probabilidade para todos os clientes ativos e escreve em AI.CHURN_SCORES.
    """
    # ── Carrega dataset ────────────────────────────────────────────────────────
    df = session.table("MART.CUSTOMER_360")

    # Label: churned = 1, outros = 0
    df = df.with_column(
        LABEL_COL,
        when(col("LIFECYCLE_STAGE") == lit("churned"), lit(1.0)).otherwise(lit(0.0))
    )

    # Preenche nulos com 0 para features numéricas
    for f in FEATURE_COLS:
        df = df.fill_na({f: 0.0})

    # ── Pipeline de treino ────────────────────────────────────────────────────
    pipeline = Pipeline(
        steps=[
            ("scaler", StandardScaler(input_cols=FEATURE_COLS, output_cols=FEATURE_COLS)),
            ("model",  LogisticRegression(
                input_cols=FEATURE_COLS,
                label_cols=[LABEL_COL],
                output_cols=[PREDICT_COL],
                max_iter=200,
                C=0.5,
            )),
        ]
    )

    train_df = df.filter(col("LIFECYCLE_STAGE").isin(["churned", "active", "at_risk"]))
    pipeline.fit(train_df)

    # ── Predição sobre clientes não-churned ───────────────────────────────────
    active_df = df.filter(col("LIFECYCLE_STAGE") != lit("churned"))
    scored_df = pipeline.predict(active_df)

    # Coleta resultados para escrever na tabela de scores
    rows = scored_df.select(
        "CUSTOMER_ID", "ORG_ID",
        PREDICT_COL,
        "HEALTH_SCORE", "NPS_SCORE", "ACTIVE_DAYS_30D",
        "DAYS_SINCE_LAST_ACTIVITY", "SLA_BREACHES", "OPEN_TICKETS", "MRR",
    ).collect()

    if not rows:
        return "ERROR: nenhum cliente ativo para pontuar"

    inserted = 0
    for r in rows:
        prob     = max(0.0, min(1.0, float(r[PREDICT_COL])))
        risk     = _risk_level(prob)
        row_dict = {c: r[c] for c in [
            "HEALTH_SCORE", "NPS_SCORE", "ACTIVE_DAYS_30D",
            "DAYS_SINCE_LAST_ACTIVITY", "SLA_BREACHES", "OPEN_TICKETS", "MRR",
        ]}
        drivers  = _top_drivers(row_dict)
        action   = _recommended_action(risk, drivers)
        arr_risk = float(r["MRR"] or 0) * 12 * prob

        drivers_json = json.dumps(drivers).replace("'", "''")
        action_esc   = action.replace("'", "''")
        customer_id  = r["CUSTOMER_ID"]
        org_id       = r["ORG_ID"]

        session.sql(f"""
            MERGE INTO AI.CHURN_SCORES tgt
            USING (
                SELECT '{customer_id}' AS customer_id, '{org_id}' AS org_id
            ) src ON (tgt.customer_id = src.customer_id AND tgt.org_id = src.org_id)
            WHEN MATCHED THEN UPDATE SET
                churn_probability        = {prob:.4f},
                risk_level               = '{risk}',
                top_drivers              = PARSE_JSON('{drivers_json}'),
                recommended_action       = '{action_esc}',
                expected_revenue_at_risk = {arr_risk:.2f},
                model_version            = '{MODEL_VERSION}',
                scored_at                = CURRENT_TIMESTAMP()
            WHEN NOT MATCHED THEN INSERT
                (org_id, customer_id, churn_probability, risk_level,
                 top_drivers, recommended_action, expected_revenue_at_risk, model_version)
            VALUES
                ('{org_id}', '{customer_id}', {prob:.4f}, '{risk}',
                 PARSE_JSON('{drivers_json}'), '{action_esc}', {arr_risk:.2f}, '{MODEL_VERSION}')
        """).collect()
        inserted += 1

    return f"OK: {inserted} clientes pontuados — modelo {MODEL_VERSION}"


from snowflake.models.recommendation_model import generate_recommendations  # noqa: E402, I001


# ── Entry point como Stored Procedure ────────────────────────────────────────

def run_churn_pipeline(session: Session, mode: str = "full") -> str:
    """
    Ponto de entrada para CALL NEXUS_APP.CORE.SP_RUN_CHURN_PIPELINE(mode).
    mode = 'score'  → apenas scoring
    mode = 'recs'   → apenas recomendações (requer scores existentes)
    mode = 'full'   → score + recomendações
    """
    results = []

    if mode in ("score", "full"):
        results.append(train_and_score(session))

    if mode in ("recs", "full"):
        results.append(generate_recommendations(session))

    return " | ".join(results)
