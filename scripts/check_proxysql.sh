#!/usr/bin/env bash
set -euo pipefail

MYSQLADMIN_BIN="${MYSQLADMIN_BIN:-$(command -v mysqladmin)}"
PROXYSQL_HOST="${PROXYSQL_HOST:-127.0.0.1}"
PROXYSQL_PORT="${PROXYSQL_PORT:-6033}"

exec "${MYSQLADMIN_BIN}" --protocol=tcp -h "${PROXYSQL_HOST}" -P "${PROXYSQL_PORT}" \
  --connect-timeout=1 ping
