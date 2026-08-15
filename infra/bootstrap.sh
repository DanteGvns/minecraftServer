# bootstrap.sh
#!/bin/bash
set -e
sudo apt update && sudo apt upgrade -y
sudo apt install -y docker.io docker-compose git rclone
sudo systemctl enable docker
sudo systemctl start docker
mkdir -p "$(pwd)/logs"
echo "Bootstrap complete."