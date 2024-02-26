#!/bin/bash

git pull

hugo

docker compose down && docker compose up -d
