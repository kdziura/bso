#!/bin/bash
set -euo pipefail

# Automation container name
CONTAINER_NAME="bso_automation"

# Script paths
SCRIPTS_DIR="/opt/scripts"
DISCOVER_SCRIPT="${SCRIPTS_DIR}/discover_hosts.sh"
SCAN_SCRIPT="${SCRIPTS_DIR}/launch_scan.sh"
REPORT_SCRIPT="${SCRIPTS_DIR}/report_completed_scans.sh"

echo "=== STARTING SCANNING PROCESS ==="

# Step 1: Host discovery
echo "Launching host discovery..."
docker exec -it "$CONTAINER_NAME" "$DISCOVER_SCRIPT"

if [ $? -ne 0 ]; then
    echo "Error during host discovery"
    exit 1
fi

# Step 2: Vulnerability scan
echo "Launching vulnerability scan..."
docker exec -it "$CONTAINER_NAME" "$SCAN_SCRIPT"

if [ $? -ne 0 ]; then
    echo "Error during vulnerability scan"
    exit 1
fi

echo "Waiting for scan completion..."
while [ $($REDIS_CLI LLEN bso:completed_tasks) -eq 0 ]; do
    sleep 5
done

# Step 3: Report generation
echo "Generating report..."
docker exec -it "$CONTAINER_NAME" "$REPORT_SCRIPT"

if [ $? -ne 0 ]; then
    echo "Error during report generation"
    exit 1
fi

echo "=== SCAN COMPLETED SUCCESSFULLY ==="
