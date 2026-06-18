"""
NEXUS AI DataOps — Recommendation Model
Gera recomendações de churn prevention com Cortex Complete.
Lê de AI.CHURN_SCORES e escreve em AI.RECOMMENDATIONS.
"""

import json

from snowflake.snowpark import Session


def generate_recommendations(session: Session, org_id: str = "ORG-DEMO-001") -> str:
    """
    Gera recomendações via Cortex Complete para clientes HIGH/MEDIUM risk
    que ainda não têm recomendação ativa nos últimos 7 dias.
    """
    rows = session.sql(f"""
        SELECT
            cs.customer_id,
            cs.org_id,
            c.name                   AS customer_name,
            cs.risk_level,
            cs.churn_probability,
            cs.recommended_action,
            cs.top_drivers,
            cs.expected_revenue_at_risk,
            c360.health_score,
            c360.nps_score,
            c360.arr,
            c360.segment,
            c360.nearest_renewal_date
        FROM AI.CHURN_SCORES cs
        JOIN CORE.CUSTOMERS c
            ON cs.customer_id = c.customer_id AND cs.org_id = c.org_id
        JOIN MART.CUSTOMER_360 c360
            ON cs.customer_id = c360.customer_id
        LEFT JOIN AI.RECOMMENDATIONS r
            ON cs.customer_id = r.entity_id
           AND r.status = 'pending'
           AND r.is_active = TRUE
           AND r.recommendation_type = 'churn_prevention'
           AND r.created_at >= DATEADD('day', -7, CURRENT_TIMESTAMP())
        WHERE cs.org_id = '{org_id}'
          AND cs.risk_level IN ('HIGH', 'MEDIUM')
          AND r.recommendation_id IS NULL
        ORDER BY cs.expected_revenue_at_risk DESC
        LIMIT 20
    """).collect()

    if not rows:
        return "OK: sem novos clientes para gerar recomendações"

    generated = 0
    for r in rows:
        drivers_raw = r["TOP_DRIVERS"]
        try:
            drivers_str = ", ".join(
                json.loads(drivers_raw) if isinstance(drivers_raw, str) else drivers_raw
            )
        except Exception:
            drivers_str = str(drivers_raw)

        prompt = (
            f"Você é um Customer Success Manager sênior. "
            f"Gere UMA recomendação de ação clara e objetiva (máximo 2 frases) para prevenir o churn "
            f"de {r['CUSTOMER_NAME']} ({r['SEGMENT']}). "
            f"ARR: US$ {r['ARR']:,.0f}. "
            f"Risk: {r['RISK_LEVEL']} ({r['CHURN_PROBABILITY']:.0%}). "
            f"Drivers: {drivers_str}. "
            f"Health Score: {r['HEALTH_SCORE']}. "
            f"NPS: {r['NPS_SCORE']}. "
            f"Renovação: {r['NEAREST_RENEWAL_DATE']}. "
            f"Responda em português, sem bullet points, focado em ação imediata."
        ).replace("'", "''")

        rec_row = session.sql(
            f"SELECT SNOWFLAKE.CORTEX.COMPLETE('mistral-large2', '{prompt}') AS rec"
        ).collect()
        rec_text = (rec_row[0]["REC"] or r["RECOMMENDED_ACTION"]).strip()

        priority   = "HIGH" if r["RISK_LEVEL"] == "HIGH" else "MEDIUM"
        impact_usd = float(r["EXPECTED_REVENUE_AT_RISK"] or 0)
        rec_esc    = rec_text.replace("'", "''")
        cid        = r["CUSTOMER_ID"]
        oid        = r["ORG_ID"]

        session.sql(f"""
            INSERT INTO AI.RECOMMENDATIONS
                (org_id, entity_id, entity_type, recommendation_type,
                 priority, recommendation_text, expected_impact_usd,
                 confidence_score, owner_role, status)
            VALUES
                ('{oid}', '{cid}', 'customer', 'churn_prevention',
                 '{priority}', '{rec_esc}', {impact_usd:.2f},
                 {r['CHURN_PROBABILITY']:.4f}, 'customer_success', 'pending')
        """).collect()
        generated += 1

    return f"OK: {generated} recomendações geradas"


def run_all_orgs(session: Session) -> str:
    """Executa generate_recommendations para todos os orgs ativos."""
    orgs = session.sql(
        "SELECT DISTINCT org_id FROM CORE.CUSTOMERS WHERE lifecycle_stage != 'churned'"
    ).collect()
    results = [generate_recommendations(session, r["ORG_ID"]) for r in orgs]
    return " | ".join(results) if results else "OK: nenhum org ativo"
