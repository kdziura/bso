#!/bin/bash
set -e

REDIS_CLI="redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT}"

echo "[discover] Clearing old host list"
$REDIS_CLI DEL bso:targets

echo "[discover] Scanning local subnets…"
for net in $(ip -4 -o addr show scope global | awk '{print $4}'); do
  nmap -sn $net -oG - | awk '/Up$/{print $2}' \
    | while read host; do
        echo "[discover] Found $host"
        $REDIS_CLI RPUSH bso:targets $host
      done
done

count=$($REDIS_CLI LLEN bso:targets)
echo "[discover] Total targets: $count"
