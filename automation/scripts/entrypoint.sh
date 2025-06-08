#!/bin/bash
set -e

echo "[entrypoint] Updating GVMD feeds…"
gvmd --update-feed

echo "[entrypoint] Setting up cron jobs…"
cat <<EOF > /etc/cron.d/bso-scan
# co 24h o 02:00 – wykrywanie hostów
0 2 * * * root /opt/scripts/discover_hosts.sh >> /var/log/bso-cron.log 2>&1
# co 24h o 02:30 – uruchomienie skanu i generowanie raportu
30 2 * * * root /opt/scripts/launch_scan.sh >> /var/log/bso-cron.log 2>&1
EOF

chmod 0644 /etc/cron.d/bso-scan
crontab /etc/cron.d/bso-scan

echo "[entrypoint] Starting cron…"
cron

echo "[entrypoint] Tailing cron log…"
tail -F /var/log/bso-cron.log

