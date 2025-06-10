#!/bin/bash
# File path: scripts/configure_cron.sh

set -euo pipefail

# Check if docker-compose or docker compose is available
if command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
elif docker compose version &> /dev/null; then
    COMPOSE_CMD="docker compose"
else
    echo "Error: Neither docker-compose nor docker compose found"
    exit 1
fi

# Get current working directory
CURRENT_DIR=$(pwd)

# Check if we're in the right directory
if [[ ! -f "docker-compose.yml" ]]; then
    echo "Error: docker-compose.yml not found in current directory"
    exit 1
fi

# Prepare cron jobs
FEED_UPDATE_JOB="0 1 * * * cd $CURRENT_DIR && $COMPOSE_CMD pull vulnerability-tests notus-data scap-data cert-bund-data dfn-cert-data data-objects report-formats && $COMPOSE_CMD up -d vulnerability-tests notus-data scap-data cert-bund-data dfn-cert-data data-objects report-formats >> /var/log/greenbone-feeds.log 2>&1"
SCAN_JOB="0 3 * * * cd $CURRENT_DIR && ./automation/scripts/run_full_scan.sh >> /var/log/greenbone-scan.log 2>&1"

# Add cron jobs if they don't exist
if ! crontab -l 2>/dev/null | grep -q "greenbone-feeds.log"; then
    (crontab -l 2>/dev/null; echo "$FEED_UPDATE_JOB") | crontab -
fi

if ! crontab -l 2>/dev/null | grep -q "run_full_scan.sh"; then
    (crontab -l 2>/dev/null; echo "$SCAN_JOB") | crontab -
fi

# Create log files
if sudo touch /var/log/greenbone-feeds.log /var/log/greenbone-scan.log 2>/dev/null; then
    sudo chmod 666 /var/log/greenbone-feeds.log /var/log/greenbone-scan.log 2>/dev/null || true
else
    touch /tmp/greenbone-feeds.log /tmp/greenbone-scan.log
    # Update cron jobs to use /tmp
    crontab -l 2>/dev/null | grep -v "greenbone-feeds.log\|run_full_scan.sh" | crontab - 2>/dev/null || true
    FEED_UPDATE_JOB_TMP="0 1 * * * cd $CURRENT_DIR && $COMPOSE_CMD pull vulnerability-tests notus-data scap-data cert-bund-data dfn-cert-data data-objects report-formats && $COMPOSE_CMD up -d vulnerability-tests notus-data scap-data cert-bund-data dfn-cert-data data-objects report-formats >> /tmp/greenbone-feeds.log 2>&1"
    SCAN_JOB_TMP="0 3 * * * cd $CURRENT_DIR && ./automation/scripts/run_full_scan.sh >> /tmp/greenbone-scan.log 2>&1"
    (crontab -l 2>/dev/null; echo "$FEED_UPDATE_JOB_TMP"; echo "$SCAN_JOB_TMP") | crontab -
fi

echo "Cron jobs configured successfully"
