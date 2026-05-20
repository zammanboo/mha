#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${MYSQL_HA_ENV:-/etc/mysql-ha.env}"
BASE_DIR_VALUE="${1:-${BASE_DIR:-}}"
PERCONA_SETUP_VALUE="${PERCONA_SETUP:-pdps-84-lts}"
SERVICE_NAME_VALUE="${SERVICE_NAME:-orchestrator}"
PROXYSQL_ADMIN_HOST_VALUE="${PROXYSQL_ADMIN_HOST:-127.0.0.1}"
PROXYSQL_ADMIN_PORT_VALUE="${PROXYSQL_ADMIN_PORT:-6032}"
PROXYSQL_ADMIN_USER_VALUE="${PROXYSQL_ADMIN_USER:-admin}"
PROXYSQL_ADMIN_PASSWORD_VALUE="${PROXYSQL_ADMIN_PASSWORD:-CHANGE_ME_PROXYSQL_ADMIN}"

if [ "$(id -u)" -ne 0 ]; then
  echo "run as root, for example: sudo $0 /opt/mysql-ha" >&2
  exit 1
fi

if [ -z "${BASE_DIR_VALUE}" ]; then
  echo "usage: sudo $0 /absolute/base/dir" >&2
  exit 1
fi

case "${BASE_DIR_VALUE}" in
  /*) ;;
  *)
    echo "BASE_DIR must be an absolute path: ${BASE_DIR_VALUE}" >&2
    exit 1
    ;;
esac

mkdir -p "${BASE_DIR_VALUE}"
mkdir -p "$(dirname "${ENV_FILE}")"

{
  printf 'BASE_DIR=%s\n' "${BASE_DIR_VALUE}"
  printf 'PERCONA_SETUP=%s\n' "${PERCONA_SETUP_VALUE}"
  printf 'SERVICE_NAME=%s\n' "${SERVICE_NAME_VALUE}"
  printf 'PROXYSQL_ADMIN_HOST=%s\n' "${PROXYSQL_ADMIN_HOST_VALUE}"
  printf 'PROXYSQL_ADMIN_PORT=%s\n' "${PROXYSQL_ADMIN_PORT_VALUE}"
  printf 'PROXYSQL_ADMIN_USER=%s\n' "${PROXYSQL_ADMIN_USER_VALUE}"
  printf 'PROXYSQL_ADMIN_PASSWORD=%s\n' "${PROXYSQL_ADMIN_PASSWORD_VALUE}"
} > "${ENV_FILE}"

chmod 0640 "${ENV_FILE}"
if id orchestrator >/dev/null 2>&1; then
  chown root:orchestrator "${ENV_FILE}"
else
  chown root:root "${ENV_FILE}"
fi

echo "registered BASE_DIR=${BASE_DIR_VALUE} in ${ENV_FILE}"
