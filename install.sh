#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/kdziura/bso.git"
REPO_DIR="bso-main"
ENV_FILE=".env"

# 1. Clone repository if not exists
test -d "$REPO_DIR" || {
  echo "Cloning repository from $REPO_URL..."
  git clone "$REPO_URL" "$REPO_DIR"
}
cd "$REPO_DIR"

# 2. Generate .env template
if [ ! -f "$ENV_FILE" ]; then
  echo "Creating .env with default values..."
  cat > "$ENV_FILE" <<EOF
# Change all values enclosed in "<>" to your own values.
GMV_HOST=127.0.0.1
GMV_PORT=9390
GMP_USERNAME=admin
GMP_PASSWORD=<gmp_pass>
REDIS_HOST=redis-server
REDIS_PORT=6379
SMTP_SERVER=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=<sender_email>
SMTP_PASSWORD=<sender_email_password>
REPORT_EMAIL=<recipient_email>
GVMD_SCAN_CONFIG_ID=daba56c8-73ec-11df-a475-002264764cea
TASK_NAME_PREFIX=BSO-AutoScan
EOF
  echo
  echo "Fill in the .env file, then rerun the same command to finish installation."
  echo "You can use the following command to edit the file:"
  echo "nano bso-main/$ENV_FILE"
  exit 0
else
  echo ".env exists, continuing."
fi

# 3. Build and start containers
echo "Building images and starting Docker containers..."

if command -v docker-compose &> /dev/null; then
  COMPOSE_CMD="docker-compose"
elif docker compose version &> /dev/null; then
  COMPOSE_CMD="docker compose"
else
  echo "Error: neither 'docker-compose' nor 'docker compose' available." >&2
  exit 1
fi

$COMPOSE_CMD pull --quiet
$COMPOSE_CMD up -d --build

# 4. Configure cron jobs
echo "Configuring cron jobs..."

# Get current working directory (full path)
CURRENT_DIR=$(pwd)

# Create backup of current crontab
echo "Creating crontab backup..."
crontab -l > crontab_backup.txt 2>/dev/null || echo "# No existing crontab" > crontab_backup.txt

# Prepare new cron jobs
# Update vulnerability feeds at 1 AM daily
FEED_UPDATE_JOB="0 1 * * * cd $CURRENT_DIR && $COMPOSE_CMD pull vulnerability-tests notus-data scap-data cert-bund-data dfn-cert-data data-objects report-formats && $COMPOSE_CMD up -d vulnerability-tests notus-data scap-data cert-bund-data dfn-cert-data data-objects report-formats >> /var/log/greenbone-feeds.log 2>&1"
# Run full scan at 3 AM daily
SCAN_JOB="0 3 * * * cd $CURRENT_DIR && ./automation/scripts/run_full_scan.sh >> /var/log/greenbone-scan.log 2>&1"

# Check if jobs already exist in crontab
if crontab -l 2>/dev/null | grep -q "greenbone-feeds.log"; then
  echo "Feed update cron job already exists, skipping..."
else
  echo "Adding feed update cron job..."
  (crontab -l 2>/dev/null; echo "$FEED_UPDATE_JOB") | crontab -
fi

if crontab -l 2>/dev/null | grep -q "run_full_scan.sh"; then
  echo "Scan cron job already exists, skipping..."
else
  echo "Adding scan cron job..."
  (crontab -l 2>/dev/null; echo "$SCAN_JOB") | crontab -
fi

# Create log files with proper permissions
echo "Creating log files..."
sudo touch /var/log/greenbone-feeds.log /var/log/greenbone-scan.log 2>/dev/null || {
  touch /tmp/greenbone-feeds.log /tmp/greenbone-scan.log
  echo "Warning: Could not create logs in /var/log, using /tmp instead"
}

# 4. Summary
echo
echo "Installation complete"
echo "Check containers: docker-compose ps"
echo " "
echo "Set up the admin password using this command: docker compose -f docker-compose.yml exec -u gvmd gvmd gvmd --user=admin --new-password=your_password"
echo "Make sure you set the same password as in the .env file - otherwise the scanner won't work!"
echo "Run this command before running the first scan: find $REPO_DIR/automation/scripts -name "*.sh" -exec chmod +x {} \;"
#echo "  • View logs: docker-compose logs -f"
