# gamerules.sh
#!/bin/bash
set -e
echo "Setting gamerules on Bedrock server..."
docker exec bedrock send-command "gamerule showcoordinates true"
docker exec bedrock send-command "gamerule keepinventory false"
docker exec bedrock send-command "gamerule dofiretick true"
echo "Gamerules applied."