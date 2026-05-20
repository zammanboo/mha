#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${MYSQL_HA_ENV:-/etc/mysql-ha.env}"
if [ -f "${ENV_FILE}" ]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

TARGET="${1:-}"
SERVICE_NAME="${SERVICE_NAME:-orchestrator}"

if [ "$(id -u)" -ne 0 ]; then
  echo "run as root, for example: sudo $0 proxy" >&2
  exit 1
fi

restart_if_present() {
  local service="$1"
  if systemctl list-unit-files --no-legend "${service}.service" 2>/dev/null | grep -q "^${service}.service"; then
    systemctl restart "${service}"
    systemctl --no-pager --full status "${service}" || true
  else
    echo "skip missing service: ${service}"
  fi
}

case "${TARGET}" in
  mysql)
    restart_if_present mysql
    ;;
  proxy)
    restart_if_present proxysql
    restart_if_present keepalived
    ;;
  orchestrator)
    restart_if_present "${SERVICE_NAME}"
    ;;
  all)
    restart_if_present mysql
    restart_if_present proxysql
    restart_if_present "${SERVICE_NAME}"
    restart_if_present keepalived
    ;;
  *)
    echo "usage: sudo $0 mysql|proxy|orchestrator|all" >&2
    exit 1
    ;;
esac
