#!/usr/bin/env bash
set -e

cd "$(dirname "$0")/../"

docker build ./ -f Dockerfile -t myapp:develop --platform linux/amd64
