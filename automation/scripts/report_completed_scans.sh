#!/bin/bash
set -euo pipefail

REDIS_CLI="redis-cli -s /run/redis/redis.sock"

echo "[reports] Checking for completed scans..."

# Check if there are any completed tasks in Redis
count=$($REDIS_CLI LLEN bso:completed_tasks)
echo "[reports] Found $count completed tasks"

if [ "$count" -eq 0 ]; then
    echo "[reports] No completed tasks to process"
    exit 0
fi

# Go through each completed task
while true; do
    # Pop a task from the completed tasks list
    TASK_ID=$($REDIS_CLI LPOP bso:completed_tasks)
    
    # If no tasks left, exit
    if [ -z "$TASK_ID" ] || [ "$TASK_ID" = "(nil)" ]; then
        echo "[reports] All completed tasks processed"
        break
    fi
    
    echo "[reports] Processing task: $TASK_ID"
    
    # Generate report for the task
    if python3 /opt/scripts/generate_report.py "$TASK_ID"; then
        echo "[reports] Successfully processed task: $TASK_ID"
    else
        echo "[reports] Failed to process task: $TASK_ID"
        # Add the task back to the list for retry
        $REDIS_CLI RPUSH bso:completed_tasks "$TASK_ID"
    fi
done

echo "[reports] Report processing completed"
