#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${MYSQL_HA_ENV:-/etc/mysql-ha.env}"
if [ -f "${ENV_FILE}" ]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

BASE_DIR="${BASE_DIR:-/opt/mysql-ha}"

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing command: $1" >&2
    exit 1
  fi
}

need mysql
need mysqladmin
need python3

for cmd in proxysql keepalived orchestrator; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "missing command: ${cmd}" >&2
    exit 1
  fi
done

python3 - <<'PY'
try:
    import pymysql
except ImportError:
    raise SystemExit("missing python module: pymysql")
PY

mysql --version
mysqladmin --version
python3 --version

if [ ! -x "${BASE_DIR}/scripts/proxysql_failover.py" ]; then
  echo "missing hook script: ${BASE_DIR}/scripts/proxysql_failover.py" >&2
  exit 1
fi

if [ ! -x "${BASE_DIR}/scripts/check_proxysql.sh" ]; then
  echo "missing ProxySQL check script: ${BASE_DIR}/scripts/check_proxysql.sh" >&2
  exit 1
fi

if [ -f /etc/orchestrator.conf.json ] && grep -q "__BASE_DIR__" /etc/orchestrator.conf.json; then
  echo "unrendered __BASE_DIR__ placeholder in /etc/orchestrator.conf.json" >&2
  exit 1
fi

if [ -f /etc/keepalived/keepalived.conf ] && grep -q "__BASE_DIR__" /etc/keepalived/keepalived.conf; then
  echo "unrendered __BASE_DIR__ placeholder in /etc/keepalived/keepalived.conf" >&2
  exit 1
fi

for config_file in \
    /etc/orchestrator.conf.json \
    /etc/keepalived/keepalived.conf \
    /etc/mysql-ha.env; do
  if [ -f "${config_file}" ] && grep -qE "CHANGE_ME" "${config_file}"; then
    echo "unset CHANGE_ME placeholder found in ${config_file}" >&2
    exit 1
  fi
done

echo "preflight ok"
