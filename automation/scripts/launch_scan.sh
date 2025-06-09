#!/bin/bash
set -euo pipefail

# Ścieżka do socketu Redis
REDIS_CLI="redis-cli -s /run/redis/redis.sock"

# 1. Pobierz unikalne hosty z Redis i wyeksportuj
HOSTS=$($REDIS_CLI LRANGE bso:targets 0 -1 | sort -u | xargs)
if [ -z "$HOSTS" ]; then
  echo "[scan] No targets found, exiting."
  exit 0
fi
export HOSTS

# 2. Utwórz nazwę zadania i wyeksportuj
TIMESTAMP=$(date +%Y%m%d%H%M)
TASK_NAME="${TASK_NAME_PREFIX}-${TIMESTAMP}"
export TASK_NAME

echo "[scan] Creating task '$TASK_NAME' for: $HOSTS"

# 3. Utwórz target i task przez Unix-socket GVMD
TASK_ID=$(python3 - <<'EOF'
import os
from gvm.connections import UnixSocketConnection
from gvm.protocols.gmp import Gmp

hosts = os.environ["HOSTS"].split()
conn = UnixSocketConnection(path="/run/gvmd/gvmd.sock")
with Gmp(conn) as gmp:
    # 3a. Ustawiamy target
    tgt_id = gmp.create_target(
        name=os.environ["TASK_NAME"] + "-target",
        hosts=hosts
    )
    # 3b. Tworzymy task
    task_id = gmp.create_task(
        name=os.environ["TASK_NAME"],
        config_id=os.environ["GVMD_SCAN_CONFIG_ID"],
        target_id=tgt_id
    )
    print(task_id)
EOF
)
echo "[scan] Task ID: $TASK_ID"
export TASK_ID

# 4. Czekaj na status "Done"
echo "[scan] Waiting for completion…"
until python3 - <<'EOF' | grep -q "Done"; do
import os, time
from gvm.connections import UnixSocketConnection
from gvm.protocols.gmp import Gmp

conn = UnixSocketConnection(path="/run/gvmd/gvmd.sock")
with Gmp(conn) as gmp:
    status = gmp.get_task(task_id=os.environ["TASK_ID"]).find("status").text
    print(status)
    if status != "Done":
        time.sleep(10)
EOF
    :
done

# 5. Eksport raportu XML→PDF
REPORT_XML="/tmp/report-${TASK_ID}.xml"
REPORT_PDF="/tmp/report-${TASK_ID}.pdf"
echo "[scan] Exporting report XML…"
gvmd --get-report "$TASK_ID" --format XML > "$REPORT_XML"
echo "[scan] Generating PDF…"
python3 /opt/scripts/generate_report.py "$REPORT_XML" "$REPORT_PDF"

# 6. Wysyłka maila
echo "[scan] Sending email…"
bash /opt/scripts/send_mail.sh "$REPORT_PDF"

echo "[scan] Done."
