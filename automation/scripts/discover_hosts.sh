#!/bin/bash
set -euo pipefail

# Ścieżka do socketu Redis
REDIS_CLI="redis-cli -s /run/redis/redis.sock"

# Tryb testowy - ustaw na "true" dla szybkich testów
TEST_MODE="${TEST_MODE:-true}"

echo "[discover] Clearing old host list"
$REDIS_CLI DEL bso:targets

if [ "$TEST_MODE" = "false" ]; then
    # TRYB TESTOWY - tylko jeden host
    echo "[discover] TEST MODE: Adding only 192.168.1.1 for quick testing..."
    $REDIS_CLI RPUSH bso:targets "192.168.1.1"
else
    # TRYB PEŁNY - skanowanie sieci
    echo "[discover] FULL MODE: Scanning network..."
    
    # 1. Wyznacz interfejs domyślny (ten, którym wychodzi ruch)
    default_route=$(/sbin/ip route show default | head -n1)
    iface=$(awk '/default/ {
      for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)
    }' <<<"$default_route")

    # 2. Pobierz CIDR dla tego interfejsu
    cidr=$(/sbin/ip -o -f inet addr show dev "$iface" | awk '{print $4}')

    echo "[discover] Scanning default subnet $cidr on interface $iface…"

    # 3. Wykonaj ping-sweep i wrzuć żywe hosty do Redis
    nmap -n -sn "$cidr" -oG - \
      | awk '/Up$/{print $2}' \
      | while read -r host; do
          echo "[discover] Found $host"
          $REDIS_CLI RPUSH bso:targets "$host"
        done
fi

# 4. Podsumowanie
count=$($REDIS_CLI LLEN bso:targets)
echo "[discover] Total targets: $count"
echo "[discover] Done."
