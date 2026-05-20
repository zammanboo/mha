#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${MYSQL_HA_ENV:-/etc/mysql-ha.env}"
BASE_DIR_VALUE="${1:-${BASE_DIR:-}}"
PERCONA_SETUP_VALUE="${PERCONA_SETUP:-pdps-84-lts}"
SERVICE_NAME_VALUE="${SERVICE_NAME:-orchestrator}"

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
} > "${ENV_FILE}"

chmod 0644 "${ENV_FILE}"

echo "registered BASE_DIR=${BASE_DIR_VALUE} in ${ENV_FILE}"
