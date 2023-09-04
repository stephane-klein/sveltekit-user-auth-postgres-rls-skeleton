#!/usr/bin/env bash
set -e

cd "$(dirname "$0")/../"

pgcli "postgres://postgrestest:passwordtest@127.0.0.1:5433/myapp"
