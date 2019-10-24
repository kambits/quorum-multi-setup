#!/bin/bash

docker rm -f $(docker ps -a | grep "quorum" | awk '{print $1}')
docker rm -f $(docker ps -a | grep "istanbul-tools" | awk '{print $1}')
sudo docker network remove $(sudo docker network ls -q)
sudo rm -rf qdata_*
sudo rm -rf istanbul_dir
sudo rm -rf genesis.json
sudo rm -rf docker-compose.yml