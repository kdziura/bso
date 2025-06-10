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
GMV_HOST=127.0.0.1
GMV_PORT=9390
GMP_USERNAME=admin
GMP_PASSWORD=bso
REDIS_HOST=redis-server
REDIS_PORT=6379
SMTP_SERVER=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=you@example.com
SMTP_PASSWORD=your_password
REPORT_EMAIL=recipient@example.com
GVMD_SCAN_CONFIG_ID=daba56c8-73ec-11df-a475-002264764cea
TASK_NAME_PREFIX=BSO-AutoScan
EOF
  echo
  echo "Fill in .env now, then rerun the same command to finish installation."
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
# 4. Summary
echo
echo "Installation complete"
echo "Check containers: docker-compose ps"
echo "Set up the admin password using this command: docker compose -f docker-compose.yml exec -u gvmd gvmd gvmd --user=admin --new-password=your_password"
echo "Make sure you set the same password as in the .env file!"
#echo "  • View logs: docker-compose logs -f"
