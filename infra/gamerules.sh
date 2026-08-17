# gamerules.sh
#!/bin/bash
set -e
# shellcheck source=lib/common.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

echo "Setting gamerules on Bedrock server..."
docker exec "$CONTAINER_NAME" send-command "gamerule showcoordinates true"
docker exec "$CONTAINER_NAME" send-command "gamerule keepinventory false"
docker exec "$CONTAINER_NAME" send-command "gamerule dofiretick true"
echo "Gamerules applied."