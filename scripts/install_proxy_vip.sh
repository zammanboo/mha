#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common_install.sh"

ensure_percona_repo
pkg_install proxysql2 keepalived
install_mysql_client
install_python_pymysql

systemctl enable --now proxysql
systemctl enable keepalived

echo "proxysql: $(command -v proxysql || true)"
echo "mysqladmin: $(command -v mysqladmin)"
systemctl --no-pager --full status proxysql || true
echo "keepalived is installed but not started here. Copy keepalived/*.conf to /etc/keepalived/keepalived.conf, then run: systemctl start keepalived"
