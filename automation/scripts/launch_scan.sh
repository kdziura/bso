#!/bin/bash
set -e

REDIS_CLI="redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT}"
HOSTS=$($REDIS_CLI LRANGE bso:targets 0 -1 | sort -u | xargs)

if [ -z "$HOSTS" ]; then
  echo "[scan] No targets found, exiting."
  exit 0
fi

TIMESTAMP=$(date +%Y%m%d%H%M)
TASK_NAME="${TASK_NAME_PREFIX}-${TIMESTAMP}"
echo "[scan] Creating task '$TASK_NAME' for: $HOSTS"

export HOSTS TASK_NAME

TASK_ID=$(python3 - <<'EOF'
import os
from gvm.connections import TLSConnection
from gvm.protocols.gmp import Gmp

hosts = os.getenv("HOSTS").split()
with TLSConnection(host=os.getenv("GMV_HOST"), port=int(os.getenv("GMV_PORT"))) as conn:
    with Gmp(conn) as gmp:
        resp = gmp.create_task(
            name=os.getenv("TASK_NAME"),
            config_id=os.getenv("GVMD_SCAN_CONFIG_ID"),
            target_hosts=hosts
        )
        print(resp.get("id"))
EOF
)

echo "[scan] Task ID: $TASK_ID"
export TASK_ID

echo "[scan] Waiting for completion…"
until python3 - <<'EOF' | grep -q "Done"; do
import os, time
from gvm.connections import TLSConnection
from gvm.protocols.gmp import Gmp

with TLSConnection(host=os.getenv("GMV_HOST"), port=int(os.getenv("GMV_PORT"))) as conn:
    with Gmp(conn) as gmp:
        status = gmp.get_task(task_id=os.getenv("TASK_ID")).find("status").text
        print(status)
        if status != "Done":
            time.sleep(10)
EOF
do :; done

REPORT_XML="/tmp/report-${TASK_ID}.xml"
REPORT_PDF="/tmp/report-${TASK_ID}.pdf"

echo "[scan] Exporting report XML…"
gvmd --get-report $TASK_ID --format XML > $REPORT_XML

echo "[scan] Generating PDF…"
python3 /opt/scripts/generate_report.py $REPORT_XML $REPORT_PDF

echo "[scan] Sending email…"
/opt/scripts/send_mail.sh $REPORT_PDF

echo "[scan] Scan and report complete."
