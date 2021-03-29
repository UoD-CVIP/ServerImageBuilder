#!/usr/bin/env bash

DOCKER_BUILDKIT=1 docker build \
 -t uodcvip/colmap:latest \
 --no-cache \
 --buildarg BASE_CONTAINER=colmap/colmap:latest \
 -f ./Dockerfile \
 --target custom \
 .