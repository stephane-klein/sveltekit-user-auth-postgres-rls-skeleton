#!/usr/bin/env bash
set -e

cd "$(dirname "$0")/../"

pgcli "postgres://webapp:password@127.0.0.1:5432/myapp"
