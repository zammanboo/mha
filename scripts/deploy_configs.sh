#!/usr/bin/env bash
set -euo pipefail

ROLE="${1:-}"
ENV_FILE="${MYSQL_HA_ENV:-/etc/mysql-ha.env}"
if [ -f "${ENV_FILE}" ]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

if [ -n "${INSTALL_DIR:-}" ] && [ -z "${BASE_DIR:-}" ]; then
  BASE_DIR="${INSTALL_DIR}"
fi

BASE_DIR="${BASE_DIR:-/opt/mysql-ha}"
FORCE="${FORCE:-0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [ "$(id -u)" -ne 0 ]; then
  echo "run as root, for example: sudo $0 primary" >&2
  exit 1
fi

if [ "${ROLE}" != "primary" ] && [ "${ROLE}" != "replica" ]; then
  echo "usage: sudo $0 primary|replica" >&2
  exit 1
fi

copy_file() {
  local src="$1"
  local dst="$2"
  local mode="${3:-0644}"

  mkdir -p "$(dirname "${dst}")"
  if [ -e "${dst}" ] && [ "${FORCE}" != "1" ]; then
    echo "skip existing ${dst}; set FORCE=1 to overwrite"
    return
  fi
  cp "${src}" "${dst}"
  chmod "${mode}" "${dst}"
}

render_file() {
  local src="$1"
  local dst="$2"
  local mode="${3:-0644}"
  local escaped_base_dir

  mkdir -p "$(dirname "${dst}")"
  if [ -e "${dst}" ] && [ "${FORCE}" != "1" ]; then
    echo "skip existing ${dst}; set FORCE=1 to overwrite"
    return
  fi

  escaped_base_dir="$(printf '%s' "${BASE_DIR}" | sed 's/[\/&]/\\&/g')"
  sed "s/__BASE_DIR__/${escaped_base_dir}/g" "${src}" > "${dst}"
  chmod "${mode}" "${dst}"
}

detect_mysql_conf_dir() {
  if [ -d /etc/mysql/conf.d ]; then
    echo /etc/mysql/conf.d
  elif [ -d /etc/my.cnf.d ]; then
    echo /etc/my.cnf.d
  else
    echo "warning: neither /etc/mysql/conf.d nor /etc/my.cnf.d found; defaulting to /etc/mysql/conf.d — verify MySQL includes this path via !includedir" >&2
    echo /etc/mysql/conf.d
  fi
}

mkdir -p "${BASE_DIR}/scripts"
copy_file "${REPO_ROOT}/scripts/proxysql_failover.py" "${BASE_DIR}/scripts/proxysql_failover.py" 0755
copy_file "${REPO_ROOT}/scripts/check_proxysql.sh" "${BASE_DIR}/scripts/check_proxysql.sh" 0755
copy_file "${REPO_ROOT}/requirements.txt" "${BASE_DIR}/requirements.txt" 0644

render_file "${REPO_ROOT}/orchestrator/orchestrator.conf.json" /etc/orchestrator.conf.json 0640

mysql_conf_dir="$(detect_mysql_conf_dir)"
if [ "${ROLE}" = "primary" ]; then
  copy_file "${REPO_ROOT}/mysql/primary.cnf" "${mysql_conf_dir}/mysql-ha.cnf" 0644
  render_file "${REPO_ROOT}/keepalived/keepalived-primary.conf" /etc/keepalived/keepalived.conf 0640
else
  copy_file "${REPO_ROOT}/mysql/replica.cnf" "${mysql_conf_dir}/mysql-ha.cnf" 0644
  render_file "${REPO_ROOT}/keepalived/keepalived-replica.conf" /etc/keepalived/keepalived.conf 0640
fi

echo "deployed runtime files for ${ROLE}"
echo "BASE_DIR: ${BASE_DIR}"
echo "hook path: ${BASE_DIR}/scripts/proxysql_failover.py"
echo "ProxySQL check: ${BASE_DIR}/scripts/check_proxysql.sh"
echo "mysql config: ${mysql_conf_dir}/mysql-ha.cnf"
echo "keepalived config: /etc/keepalived/keepalived.conf"
echo "orchestrator config: /etc/orchestrator.conf.json"
