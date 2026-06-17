{{
    config(
        alias='churn_features',
        materialized='table',
        tags=["mart", "churn", "ml", "gold"],
        post_hook=[
            "ALTER TABLE {{ this }} CLUSTER BY (org_id, churn_risk_level)",
            "GRANT SELECT ON TABLE {{ this }} TO ROLE NEXUS_ANALYST"
        ]
    )
}}

-- Feature store para o modelo de churn (Snowpark ML LogisticRegression).
-- Expõe exatamente as colunas em FEATURE_COLS de churn_model.py
-- mais o label histórico IS_CHURNED para treino.

with base as (
    select
        c.customer_id,
        c.org_id,
        c.customer_name,
        c.segment,
        c.region,
        c.industry,
        c.lifecycle_stage,

        -- Features numéricas (FEATURE_COLS em churn_model.py)
        coalesce(c.health_score, 50)                          as health_score,
        coalesce(c.nps_score, 0)                              as nps_score,
        coalesce(c.churn_probability, 0.1)                    as churn_probability,
        coalesce(c.events_30d, 0)                             as events_30d,
        coalesce(c.active_days_30d, 0)                        as active_days_30d,
        coalesce(c.days_since_last_activity, 999)             as days_since_last_activity,
        coalesce(c.open_tickets, 0)                           as open_tickets,
        coalesce(c.sla_breaches, 0)                           as sla_breaches,
        coalesce(c.mrr, 0)                                    as mrr,

        -- Features adicionais úteis para engenharia futura
        coalesce(c.arr, 0)                                    as arr,
        coalesce(c.total_seats, 0)                            as total_seats,
        coalesce(c.events_7d, 0)                              as events_7d,
        coalesce(c.features_used, 0)                          as features_used,
        coalesce(c.sla_breaches_30d, 0)                       as sla_breaches_30d,
        coalesce(c.tickets_30d, 0)                            as tickets_30d,
        coalesce(c.ai_invocations_30d, 0)                     as ai_invocations_30d,
        c.usage_trend,
        c.churn_risk_level,

        -- Renewal proximity (risco de cancelamento aumenta próximo ao vencimento)
        coalesce(c.days_to_renewal, 365)                      as days_to_renewal,

        -- Label histórico para treinamento supervisionado
        case when c.lifecycle_stage = 'churned' then 1 else 0 end as is_churned,

        current_timestamp()                                   as _feature_computed_at

    from {{ ref('customer_360') }} c
),

-- Ratios derivados (features de segunda ordem)
enriched as (
    select
        *,

        -- Taxa de tickets por assento ativo
        case when total_seats > 0
            then round(open_tickets * 1.0 / total_seats, 3)
            else 0
        end                                                   as tickets_per_seat,

        -- Queda de uso (eventos 7d vs proporcional 30d)
        case when events_30d > 0
            then round((events_7d * 4.3) / events_30d, 2)
            else 1.0
        end                                                   as usage_velocity_ratio,

        -- Score composto de engajamento (0-1)
        round(
            (
                least(active_days_30d / 20.0, 1.0) * 0.5
                + least(events_30d / 500.0, 1.0)    * 0.3
                + least(features_used / 10.0, 1.0)  * 0.2
            ), 3
        )                                                     as engagement_score

    from base
)

select * from enriched
