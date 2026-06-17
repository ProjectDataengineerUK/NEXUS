{% macro health_score(churn_probability, nps_normalized, usage_points, sla_points) %}
    least(100, greatest(0, round(
        (1 - {{ churn_probability }}) * 35
        + {{ nps_normalized }}        * 0.30
        + {{ usage_points }}          * 0.25
        + {{ sla_points }}            * 0.10
    , 1)))
{% endmacro %}


{% macro usage_trend(events_7d, events_30d, threshold=0.20) %}
    case
        when {{ events_7d }} > {{ events_30d }} / 4.0 * (1 + {{ threshold }}) then 'up'
        when {{ events_7d }} < {{ events_30d }} / 4.0 * (1 - {{ threshold }}) then 'down'
        when {{ events_30d }} = 0                                              then 'no_data'
        else                                                                        'stable'
    end
{% endmacro %}


{% macro churn_risk_level(probability, high_threshold=None, medium_threshold=None) %}
    {%- set high = high_threshold   or var('churn_high_threshold',   0.70) -%}
    {%- set med  = medium_threshold or var('churn_medium_threshold', 0.40) -%}
    case
        when {{ probability }} >= {{ high }} then 'HIGH'
        when {{ probability }} >= {{ med }}  then 'MEDIUM'
        else                                      'LOW'
    end
{% endmacro %}
