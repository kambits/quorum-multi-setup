#!/bin/bash
./cleaner.sh
./setup.sh
docker-compose up -d
docker ps -a