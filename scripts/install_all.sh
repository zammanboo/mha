#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"${SCRIPT_DIR}/install_mysql_node.sh"
"${SCRIPT_DIR}/install_proxy_vip.sh"
"${SCRIPT_DIR}/install_orchestrator.sh"

echo "all HA packages installed"
