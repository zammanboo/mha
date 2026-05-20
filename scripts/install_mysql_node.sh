#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common_install.sh"

ensure_percona_repo
pkg_install percona-server-server percona-xtrabackup-84 percona-toolkit
install_mysql_client
install_python_pymysql

systemctl enable --now mysql

echo "mysql: $(command -v mysql)"
echo "mysqladmin: $(command -v mysqladmin)"
mysql --version
systemctl --no-pager --full status mysql || true
