#!/usr/bin/env python3
"""
Recria o Native App de teste (NEXUS_AI_DATAOPS_TEST) do zero.

Uso:
    export SNOWFLAKE_ACCOUNT="MYORG-AB12345"
    export SNOWFLAKE_USER="NEXUS_DEPLOY_USER"
    export SNOWFLAKE_PASSWORD="..."
    python3 scripts/redeploy_dev_app.py

Ou com credenciais inline:
    python3 scripts/redeploy_dev_app.py --account MYORG-AB12345 --user admin --password s3cr3t
"""

import argparse
import glob
import os
import sys

import snowflake.connector


def parse_args():
    p = argparse.ArgumentParser(description="Redeploy NEXUS dev Native App")
    p.add_argument("--account",  default=os.getenv("SNOWFLAKE_ACCOUNT"))
    p.add_argument("--user",     default=os.getenv("SNOWFLAKE_USER"))
    p.add_argument("--password", default=os.getenv("SNOWFLAKE_PASSWORD"))
    p.add_argument("--role",     default="ACCOUNTADMIN")
    p.add_argument("--warehouse",default="NEXUS_COMPUTE_WH")
    p.add_argument("--app",      default="NEXUS_AI_DATAOPS_TEST")
    p.add_argument("--pkg",      default="NEXUS_AI_DATAOPS_PKG")
    p.add_argument("--vslug",    default="vdev")
    return p.parse_args()


def main():
    args = parse_args()

    missing = [k for k in ("account", "user", "password") if not getattr(args, k)]
    if missing:
        print(f"Erro: variáveis ausentes: {', '.join(m.upper() for m in missing)}")
        print("Defina SNOWFLAKE_ACCOUNT, SNOWFLAKE_USER, SNOWFLAKE_PASSWORD ou use --help")
        sys.exit(1)

    print(f"\n[NEXUS redeploy] conta={args.account}  app={args.app}  pkg={args.pkg}\n")

    conn = snowflake.connector.connect(
        account=args.account,
        user=args.user,
        password=args.password,
        role=args.role,
        warehouse=args.warehouse,
    )
    cs = conn.cursor()

    PKG   = args.pkg
    VSLUG = args.vslug
    APP   = args.app
    STAGE = f"@{PKG}.PUBLIC.APP_STAGE/{VSLUG}"

    def run(sql, label=""):
        try:
            cs.execute(sql)
            tag = label or sql[:60].replace("\n", " ")
            print(f"  ✓ {tag}")
            return True
        except Exception as e:
            tag = label or sql[:60].replace("\n", " ")
            print(f"  ⚠ {tag} → {e}")
            return False

    # ── 1. Garantir package e stage ──────────────────────────────────────────
    print("[1/4] Garantindo Application Package e Stage...")
    run(f"CREATE APPLICATION PACKAGE IF NOT EXISTS {PKG}", "package ok")
    run(f"CREATE STAGE IF NOT EXISTS {PKG}.PUBLIC.APP_STAGE DIRECTORY = (ENABLE = TRUE)", "stage ok")

    # ── 2. Upload de artefatos ───────────────────────────────────────────────
    print("\n[2/4] Fazendo upload dos artefatos...")

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    def upload_glob(pattern, base, prefix):
        for f in sorted(glob.glob(os.path.join(root, pattern), recursive=True)):
            if "__pycache__" in f:
                continue
            rel     = os.path.relpath(f, os.path.join(root, base))
            rel_dir = os.path.dirname(rel)
            dest    = f"{STAGE}/{prefix}/{rel_dir}/" if rel_dir else f"{STAGE}/{prefix}/"
            run(f"PUT file://{f} {dest} OVERWRITE=TRUE AUTO_COMPRESS=FALSE",
                f"upload {prefix}/{rel}")

    for core_file in ["snowflake/native_app/manifest.yml",
                      "snowflake/native_app/setup_script.sql",
                      "snowflake/native_app/readme.md"]:
        full = os.path.join(root, core_file)
        if os.path.exists(full):
            run(f"PUT file://{full} {STAGE}/ OVERWRITE=TRUE AUTO_COMPRESS=FALSE",
                f"upload {core_file}")

    upload_glob("app/streamlit/**/*.*",                     "app/streamlit",    "streamlit")
    upload_glob("snowflake/cortex/semantic_models/*.yaml",  "snowflake/cortex", "cortex")
    upload_glob("snowflake/cortex/agents/*.yaml",           "snowflake/cortex", "cortex")
    upload_glob("snowflake/cortex/stored_procedures/*.sql", "snowflake/cortex", "cortex")
    upload_glob("snowflake/models/*.py",                    "snowflake",        "models")

    # ── 3. Versão / Patch ────────────────────────────────────────────────────
    print("\n[3/4] Registrando versão/patch...")

    rows = cs.execute(f"SHOW VERSIONS IN APPLICATION PACKAGE {PKG}").fetchall()
    col  = [d[0].upper() for d in cs.description]
    version_exists = any(
        row[col.index("VERSION")].upper() == VSLUG.upper()
        for row in rows
    )

    if version_exists:
        run(f"ALTER APPLICATION PACKAGE {PKG} ADD PATCH FOR VERSION {VSLUG} USING '{STAGE}'",
            f"ADD PATCH → {VSLUG}")
    else:
        run(f"ALTER APPLICATION PACKAGE {PKG} ADD VERSION {VSLUG} USING '{STAGE}'",
            f"ADD VERSION {VSLUG}")
        run(f"ALTER APPLICATION PACKAGE {PKG} MODIFY RELEASE CHANNEL DEFAULT ADD VERSION {VSLUG}",
            "canal DEFAULT")

    # ── 4. Drop + Recreate do app de teste ──────────────────────────────────
    print(f"\n[4/4] Recriando {APP} (isso re-executa o setup_script.sql)...")

    run(f"DROP APPLICATION IF EXISTS {APP} CASCADE", f"DROP {APP}")
    run(f"""
        CREATE APPLICATION {APP}
            FROM APPLICATION PACKAGE {PKG}
            USING @{PKG}.PUBLIC.APP_STAGE/{VSLUG}
            COMMENT = 'Dev test — auto-recreated'
    """, f"CREATE APPLICATION {APP}")
    run(f"GRANT APPLICATION ROLE {APP}.NEXUS_ADMIN  TO ROLE ACCOUNTADMIN")
    run(f"GRANT APPLICATION ROLE {APP}.NEXUS_ANALYST TO ROLE ACCOUNTADMIN")

    cs.close()
    conn.close()

    print(f"\n✅  {APP} recriado com schema atualizado.")
    print(f"   Acesse: Snowflake → Apps → {APP}\n")


if __name__ == "__main__":
    main()
