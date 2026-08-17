#!/bin/bash
set -e
sudo apt update && sudo apt upgrade -y
sudo apt install -y docker.io docker-compose-plugin git rclone
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker "$USER"
sudo docker compose version >/dev/null
mkdir -p "$(pwd)/logs"
echo "Bootstrap complete. Restart WSL before using Docker without sudo."