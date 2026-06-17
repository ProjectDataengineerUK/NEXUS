# NEXUS AI DataOps

**Enterprise AI Command Center for Snowflake**

Transform your Snowflake into an intelligent decision system with Customer & Revenue Intelligence powered by Cortex AI.

## Features

- **Customer 360** — Unified customer view with health score, churn risk, and lifecycle stage
- **Executive Command** — Revenue dashboards, ARR/MRR trends, and KPI overview
- **AI Chat** — Natural language queries over your business data via Cortex Analyst
- **Document Intelligence** — Contract and document processing with Cortex Document AI
- **Recommendations** — AI-generated action recommendations for CS and Sales teams
- **Data Quality** — Pipeline health monitoring and data freshness tracking
- **Admin** — Configuration, RBAC management, and audit log viewer

## Requirements

- Snowflake Enterprise Edition or higher
- Cortex AI enabled on your account

## Setup

After installation, grant the required application roles to your users:

```sql
GRANT APPLICATION ROLE NEXUS_AI_DATAOPS.NEXUS_ADMIN   TO ROLE <your_admin_role>;
GRANT APPLICATION ROLE NEXUS_AI_DATAOPS.NEXUS_ANALYST  TO ROLE <your_analyst_role>;
GRANT APPLICATION ROLE NEXUS_AI_DATAOPS.NEXUS_VIEWER   TO ROLE <your_viewer_role>;
```

## Support

Contact: support@nexus-ai-dataops.io
