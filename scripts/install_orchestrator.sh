#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/common_install.sh"

SERVICE_NAME="${SERVICE_NAME:-orchestrator}"

install_orchestrator_packages() {
  ensure_percona_repo
  pkg_install percona-orchestrator percona-orchestrator-cli percona-orchestrator-client
  install_python_pymysql
}

install_config_if_missing() {
  if [ ! -f /etc/orchestrator.conf.json ]; then
    local escaped_base_dir
    escaped_base_dir="$(printf '%s' "${BASE_DIR}" | sed 's/[\/&]/\\&/g')"
    sed "s/__BASE_DIR__/${escaped_base_dir}/g" \
      "${REPO_ROOT}/orchestrator/orchestrator.conf.json" > /etc/orchestrator.conf.json
    chmod 0640 /etc/orchestrator.conf.json
  fi
}

ensure_runtime_user() {
  if ! id orchestrator >/dev/null 2>&1; then
    useradd --system --home /var/lib/orchestrator --shell /usr/sbin/nologin orchestrator
  fi
  mkdir -p /var/lib/orchestrator
  chown orchestrator:orchestrator /var/lib/orchestrator
}

install_service_if_missing() {
  if systemctl list-unit-files --no-legend "${SERVICE_NAME}.service" 2>/dev/null | grep -q "^${SERVICE_NAME}.service"; then
    return
  fi

  local orch_bin
  orch_bin="$(command -v orchestrator || true)"
  if [ -z "${orch_bin}" ]; then
    echo "orchestrator binary was not found after package installation" >&2
    exit 1
  fi

  cp "${REPO_ROOT}/systemd/orchestrator.service" "/etc/systemd/system/${SERVICE_NAME}.service"
  sed -i "s#ExecStart=/usr/local/bin/orchestrator http#ExecStart=${orch_bin} http#" \
    "/etc/systemd/system/${SERVICE_NAME}.service"
}

main() {
  install_orchestrator_packages
  ensure_runtime_user
  install_config_if_missing
  install_service_if_missing

  systemctl daemon-reload
  systemctl enable --now "${SERVICE_NAME}"

  echo "orchestrator binary: $(command -v orchestrator)"
  echo "orchestrator-client: $(command -v orchestrator-client || true)"
  systemctl --no-pager --full status "${SERVICE_NAME}" || true
}

main "$@"
