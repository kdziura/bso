#!/bin/bash
set -euo pipefail

# Path to Redis CLI
REDIS_CLI="redis-cli -s /run/redis/redis.sock"

# Default GMP profile
GMP_USERNAME="${GMP_USERNAME:-admin}"
GMP_PASSWORD="${GMP_PASSWORD:-bso}"

# 1. Get hosts from Redis
HOSTS=$($REDIS_CLI LRANGE bso:targets 0 -1 | sort -u | xargs)
if [ -z "$HOSTS" ]; then
  echo "[scan] No targets found, exiting."
  exit 0
fi
export HOSTS

# 2. Create task name (with timestamp)
TIMESTAMP=$(date +%Y%m%d%H%M)
TASK_NAME="${TASK_NAME_PREFIX:-BSO-AutoScan}-${TIMESTAMP}"
export TASK_NAME
export GMP_USERNAME
export GMP_PASSWORD

echo "[scan] Creating task '$TASK_NAME' for: $HOSTS"

# 3. Create task and target in GVM
TASK_ID=$(python3 - <<'EOF'
import warnings
warnings.filterwarnings("ignore", message=".*Remote manager daemon uses a newer GMP version.*")
import os
import sys
from gvm.connections import UnixSocketConnection
from gvm.protocols.gmp import Gmp
from gvm.transforms import EtreeCheckCommandTransform
from gvm.errors import GvmError

hosts = os.environ["HOSTS"].split()
username = os.environ["GMP_USERNAME"]
password = os.environ["GMP_PASSWORD"]

conn = UnixSocketConnection(path="/run/gvmd/gvmd.sock")
transform = EtreeCheckCommandTransform()

try:
    with Gmp(connection=conn, transform=transform) as gmp:
        gmp.authenticate(username, password)
        print(f"Authenticated as {username}", file=sys.stderr)
        
        scanners = gmp.get_scanners()
        scanner_list = scanners.xpath("scanner")
        if not scanner_list:
            raise Exception("No scanners found")
        
        # Pick OpenVAS
        scanner_id = None
        scanner_name = None
        for scanner in scanner_list:
            name = scanner.find('name').text
            if 'OpenVAS' in name or 'Default' in name:
                scanner_id = scanner.get('id')
                scanner_name = name
                break
        if not scanner_id:
            scanner_id = scanner_list[0].get('id')
            scanner_name = scanner_list[0].find('name').text
        
        print(f"Using scanner: {scanner_name} (ID: {scanner_id})", file=sys.stderr)
        
        # Get port lists
        port_lists = gmp.get_port_lists()
        port_list_options = port_lists.xpath("port_list")
        if not port_list_options:
            raise Exception("No port lists found")
        port_list_id = None
        port_list_name = None
        
        # Port lists
        preferred_ports = ['All IANA assigned TCP', 'OpenVAS Default', 'Full TCP', 'All TCP']
        
        for preferred in preferred_ports:
            for port_list in port_list_options:
                name = port_list.find('name').text
                if preferred in name:
                    port_list_id = port_list.get('id')
                    port_list_name = name
                    break
            if port_list_id:
                break
        if not port_list_id:
            port_list_id = port_list_options[0].get('id')
            port_list_name = port_list_options[0].find('name').text
        
        print(f"Using port list: {port_list_name} (ID: {port_list_id})", file=sys.stderr)
        try:
            configs = gmp.get_scan_configs()
        except AttributeError:
            configs = gmp.get_configs()
        
        config_list = configs.xpath("config")
        if not config_list:
            raise Exception("No scan configs found")
        config_id = None
        config_name = None
        preferred_configs = ['Full and fast', 'Discovery', 'System Discovery']
        
        for preferred in preferred_configs:
            for config in config_list:
                name = config.find('name').text
                if preferred in name:
                    config_id = config.get('id')
                    config_name = name
                    break
            if config_id:
                break
        if not config_id:
            config_id = config_list[0].get('id')
            config_name = config_list[0].find('name').text
        
        print(f"Using config: {config_name} (ID: {config_id})", file=sys.stderr)
        
        # Create target
        target_response = gmp.create_target(
            name=os.environ["TASK_NAME"] + "-target",
            hosts=hosts,
            port_list_id=port_list_id  # KLUCZOWE - dodane port_list_id
        )
        tgt_id = target_response.get('id')
        print(f"Created target with ID: {tgt_id}", file=sys.stderr)
        
        # Create task
        task_response = gmp.create_task(
            name=os.environ["TASK_NAME"],
            config_id=config_id,
            target_id=tgt_id,
            scanner_id=scanner_id
        )
        task_id = task_response.get('id')
        print(task_id)

except GvmError as e:
    print(f"GVM Error: {e}", file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
EOF
)

if [ $? -ne 0 ]; then
    echo "[scan] Failed to create task"
    exit 1
fi

echo "[scan] Task ID: $TASK_ID"
export TASK_ID

# 4. Launch scan
echo "[scan] Starting scan..."
python3 - <<'EOF'
import warnings
warnings.filterwarnings("ignore", message=".*Remote manager daemon uses a newer GMP version.*")
import os
import sys
from gvm.connections import UnixSocketConnection
from gvm.protocols.gmp import Gmp
from gvm.transforms import EtreeCheckCommandTransform
from gvm.errors import GvmError

conn = UnixSocketConnection(path="/run/gvmd/gvmd.sock")
transform = EtreeCheckCommandTransform()

try:
    with Gmp(connection=conn, transform=transform) as gmp:
        gmp.authenticate(os.environ["GMP_USERNAME"], os.environ["GMP_PASSWORD"])
        gmp.start_task(task_id=os.environ["TASK_ID"])
        print("Scan started successfully", file=sys.stderr)
except GvmError as e:
    print(f"Failed to start scan: {e}", file=sys.stderr)
    sys.exit(1)
EOF

if [ $? -ne 0 ]; then
    echo "[scan] Failed to start scan"
    exit 1
fi

# 5. Wait for scan to complete
echo "[scan] Waiting for completion…"
while true; do
    STATUS=$(python3 - <<'EOF'
import warnings
warnings.filterwarnings("ignore", message=".*Remote manager daemon uses a newer GMP version.*")
import os
import sys
from gvm.connections import UnixSocketConnection
from gvm.protocols.gmp import Gmp
from gvm.transforms import EtreeCheckCommandTransform

conn = UnixSocketConnection(path="/run/gvmd/gvmd.sock")
transform = EtreeCheckCommandTransform()

try:
    with Gmp(connection=conn, transform=transform) as gmp:
        gmp.authenticate(os.environ["GMP_USERNAME"], os.environ["GMP_PASSWORD"])
        tasks = gmp.get_tasks()
        task_id = os.environ["TASK_ID"]
        task_elements = tasks.xpath(f"task[@id='{task_id}']")

        if not task_elements:
            print("Task not found", file=sys.stderr)
            sys.exit(1)
        
        task = task_elements[0]
        status = task.find("status").text
        progress = task.find("progress")
        
        if progress is not None and progress.text:
            print(f"{status} ({progress.text}%)")
        else:
            print(status)
            
except Exception as e:
    print(f"Monitoring error: {str(e)}", file=sys.stderr)
    print("Running")  # Fallback - continue monitoring
EOF
)
    
    echo "[scan] Current status: $STATUS"
    
    # Check if scan is done
    if [[ "$STATUS" == "Done"* ]] || [[ "$STATUS" == "Stopped"* ]] || [[ "$STATUS" == "Interrupted"* ]]; then
        break
    fi
    
    # Check for errors
    if [[ "$STATUS" == *"Error"* ]] && [[ "$STATUS" != *"Monitoring error"* ]]; then
        echo "[scan] Critical error detected, stopping monitoring"
        break
    fi
    
    sleep 30
done


# 6. Export task ID to Redis for report generation
echo "[scan] Saving task ID to Redis for report generation..."
$REDIS_CLI RPUSH bso:completed_tasks "$TASK_ID"

echo "[scan] Scan completed. Task ID: $TASK_ID"
