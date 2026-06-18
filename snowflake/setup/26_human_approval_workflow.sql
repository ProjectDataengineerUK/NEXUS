-- =============================================================================
-- NEXUS AI DataOps — Human Approval Workflow
-- Ações sensíveis geradas pela IA requerem aprovação de um humano antes de
-- serem executadas. Fila de aprovação, auditoria e notificação via Slack.
-- =============================================================================

USE ROLE NEXUS_ADMIN;
USE DATABASE NEXUS_APP;
USE SCHEMA CORE;

-- ─── Tabela de aprovações pendentes ──────────────────────────────────────────

CREATE TABLE IF NOT EXISTS CORE.APPROVAL_QUEUE (
    approval_id         VARCHAR(36)     DEFAULT UUID_STRING() NOT NULL,
    org_id              VARCHAR(50)     NOT NULL,
    action_type         VARCHAR(100)    NOT NULL,  -- SEND_EMAIL | EXECUTE_PLAYBOOK | ESCALATE | DISMISS_CUSTOMER | API_CALL
    action_payload      VARIANT         NOT NULL,  -- JSON com todos os parâmetros da ação
    risk_level          VARCHAR(20)     DEFAULT 'MEDIUM',  -- LOW | MEDIUM | HIGH | CRITICAL
    requested_by        VARCHAR(200)    NOT NULL,  -- agente ou usuário que originou a ação
    request_context     VARCHAR(4000),             -- por que esta ação foi sugerida
    status              VARCHAR(30)     DEFAULT 'pending',  -- pending | approved | rejected | expired | executed
    approved_by         VARCHAR(200),
    rejection_reason    VARCHAR(1000),
    expires_at          TIMESTAMP_TZ    DEFAULT DATEADD('hour', 48, CURRENT_TIMESTAMP()),
    created_at          TIMESTAMP_TZ    DEFAULT CURRENT_TIMESTAMP(),
    updated_at          TIMESTAMP_TZ    DEFAULT CURRENT_TIMESTAMP(),
    executed_at         TIMESTAMP_TZ,
    execution_result    VARCHAR(2000),
    PRIMARY KEY (approval_id)
);

-- Clustering key para consultas frequentes por org e status
ALTER TABLE CORE.APPROVAL_QUEUE CLUSTER BY (org_id, status);


-- ─── SP: Submeter ação para aprovação ────────────────────────────────────────

CREATE OR REPLACE PROCEDURE CORE.SUBMIT_FOR_APPROVAL(
    org_id          VARCHAR,
    action_type     VARCHAR,
    action_payload  VARIANT,
    risk_level      VARCHAR,
    requested_by    VARCHAR,
    request_context VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    v_approval_id VARCHAR;
    v_msg         VARCHAR;
BEGIN
    v_approval_id := UUID_STRING();

    INSERT INTO CORE.APPROVAL_QUEUE
        (approval_id, org_id, action_type, action_payload, risk_level,
         requested_by, request_context)
    VALUES
        (:v_approval_id, :org_id, :action_type, :action_payload,
         :risk_level, :requested_by, :request_context);

    -- Notificar via Slack para ações HIGH/CRITICAL
    IF (:risk_level IN ('HIGH', 'CRITICAL')) THEN
        CALL CORE.SEND_SLACK_ALERT(
            '#nexus-approvals',
            '⏳ Aprovação Necessária: ' || :action_type,
            'Ação de risco ' || :risk_level || ' aguardando aprovação.\n' ||
            'Solicitante: ' || :requested_by || '\n' ||
            'Contexto: ' || LEFT(:request_context, 300) || '\n' ||
            'ID: ' || :v_approval_id,
            :risk_level
        );
    END IF;

    RETURN v_approval_id;
END;
$$;


-- ─── SP: Aprovar ação ─────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE CORE.APPROVE_ACTION(
    approval_id VARCHAR,
    approved_by VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    v_count INTEGER;
BEGIN
    UPDATE CORE.APPROVAL_QUEUE
    SET
        status      = 'approved',
        approved_by = :approved_by,
        updated_at  = CURRENT_TIMESTAMP()
    WHERE approval_id = :approval_id
      AND status      = 'pending'
      AND expires_at  > CURRENT_TIMESTAMP();

    v_count := SQLROWCOUNT;

    IF (v_count = 0) THEN
        RETURN 'ERROR: Approval not found, already actioned, or expired.';
    END IF;

    -- Registra no audit log
    INSERT INTO NEXUS_APP.AUDIT.ACTION_LOG
        (org_id, user_name, role_name, action_type, entity_type, entity_id, payload, status)
    SELECT org_id, :approved_by, 'HUMAN', 'APPROVE', 'APPROVAL_QUEUE', :approval_id,
           OBJECT_CONSTRUCT('action_type', action_type, 'risk_level', risk_level), 'completed'
    FROM CORE.APPROVAL_QUEUE WHERE approval_id = :approval_id;

    RETURN 'OK:APPROVED';
END;
$$;


-- ─── SP: Rejeitar ação ────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE CORE.REJECT_ACTION(
    approval_id      VARCHAR,
    rejected_by      VARCHAR,
    rejection_reason VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN
    UPDATE CORE.APPROVAL_QUEUE
    SET
        status           = 'rejected',
        approved_by      = :rejected_by,
        rejection_reason = :rejection_reason,
        updated_at       = CURRENT_TIMESTAMP()
    WHERE approval_id = :approval_id
      AND status      = 'pending';

    INSERT INTO NEXUS_APP.AUDIT.ACTION_LOG
        (org_id, user_name, role_name, action_type, entity_type, entity_id, payload, status)
    SELECT org_id, :rejected_by, 'HUMAN', 'REJECT', 'APPROVAL_QUEUE', :approval_id,
           OBJECT_CONSTRUCT('reason', :rejection_reason), 'completed'
    FROM CORE.APPROVAL_QUEUE WHERE approval_id = :approval_id;

    RETURN 'OK:REJECTED';
END;
$$;


-- ─── Task: expirar aprovações vencidas ────────────────────────────────────────

CREATE OR REPLACE TASK CORE.TASK_EXPIRE_APPROVALS
    WAREHOUSE = NEXUS_COMPUTE_WH
    SCHEDULE  = 'USING CRON 0 * * * * UTC'
    COMMENT   = 'Hourly: expire pending approvals past their deadline'
AS
UPDATE CORE.APPROVAL_QUEUE
SET status     = 'expired',
    updated_at = CURRENT_TIMESTAMP()
WHERE status    = 'pending'
  AND expires_at < CURRENT_TIMESTAMP();

ALTER TASK CORE.TASK_EXPIRE_APPROVALS RESUME;


-- ─── View: dashboard da fila de aprovações ───────────────────────────────────

CREATE OR REPLACE VIEW CORE.V_APPROVAL_QUEUE AS
SELECT
    approval_id,
    org_id,
    action_type,
    risk_level,
    requested_by,
    LEFT(request_context, 200)          AS context_preview,
    status,
    approved_by,
    rejection_reason,
    TO_CHAR(created_at, 'YYYY-MM-DD HH24:MI') AS created_at,
    TO_CHAR(expires_at, 'YYYY-MM-DD HH24:MI') AS expires_at,
    DATEDIFF('hour', CURRENT_TIMESTAMP(), expires_at) AS hours_remaining
FROM CORE.APPROVAL_QUEUE
ORDER BY
    CASE risk_level WHEN 'CRITICAL' THEN 1 WHEN 'HIGH' THEN 2 WHEN 'MEDIUM' THEN 3 ELSE 4 END,
    created_at DESC;
