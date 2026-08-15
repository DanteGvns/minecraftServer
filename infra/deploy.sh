# deploy.sh
#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
echo "Pulling latest Bedrock image..."
docker compose pull
echo "Starting Bedrock container..."
docker compose up -d
sleep 10
echo "Applying gamerules..."
bash "$SCRIPT_DIR/gamerules.sh"
echo "Deploy complete."