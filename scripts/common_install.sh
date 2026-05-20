#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${MYSQL_HA_ENV:-/etc/mysql-ha.env}"
if [ -f "${ENV_FILE}" ]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

BASE_DIR="${BASE_DIR:-/opt/mysql-ha}"
PERCONA_SETUP="${PERCONA_SETUP:-pdps-84-lts}"

if [ "$(id -u)" -ne 0 ]; then
  echo "run as root, for example: sudo $0" >&2
  exit 1
fi

need() {
  command -v "$1" >/dev/null 2>&1
}

detect_pkg_mgr() {
  if need apt-get; then
    echo apt
  elif need dnf; then
    echo dnf
  elif need yum; then
    echo yum
  else
    echo "unsupported OS: apt-get, dnf, or yum is required" >&2
    exit 1
  fi
}

pkg_update() {
  case "$(detect_pkg_mgr)" in
    apt) apt-get update ;;
    dnf) dnf makecache ;;
    yum) yum makecache ;;
  esac
}

pkg_install() {
  case "$(detect_pkg_mgr)" in
    apt) apt-get install -y "$@" ;;
    dnf) dnf install -y "$@" ;;
    yum) yum install -y "$@" ;;
  esac
}

pkg_install_best_effort() {
  local package
  for package in "$@"; do
    if pkg_install "${package}"; then
      return 0
    fi
  done
  return 1
}

install_percona_release_deb() {
  apt-get update
  apt-get install -y ca-certificates curl gnupg
  curl -fsSL --retry 3 -o /tmp/percona-release_latest.generic_all.deb \
    https://repo.percona.com/apt/percona-release_latest.generic_all.deb
  dpkg-deb --info /tmp/percona-release_latest.generic_all.deb >/dev/null 2>&1 || {
    echo "downloaded Percona release package is not a valid .deb; aborting" >&2
    rm -f /tmp/percona-release_latest.generic_all.deb
    exit 1
  }
  apt-get install -y /tmp/percona-release_latest.generic_all.deb
  rm -f /tmp/percona-release_latest.generic_all.deb
}

install_percona_release_rpm() {
  local installer="https://repo.percona.com/yum/percona-release-latest.noarch.rpm"
  if need dnf; then
    dnf install -y "${installer}"
  else
    yum install -y "${installer}"
  fi
}

ensure_percona_repo() {
  case "$(detect_pkg_mgr)" in
    apt)
      if ! need percona-release; then
        install_percona_release_deb
      fi
      ;;
    dnf|yum)
      if ! need percona-release; then
        install_percona_release_rpm
      fi
      ;;
  esac

  percona-release enable "${PERCONA_SETUP}"
  pkg_update
}

install_python_pymysql() {
  case "$(detect_pkg_mgr)" in
    apt)
      pkg_install python3 python3-pymysql
      ;;
    dnf|yum)
      if ! pkg_install_best_effort python3-PyMySQL python3-pymysql; then
        pkg_install python3 python3-pip
        python3 -m pip install PyMySQL
      fi
      ;;
  esac
}

install_mysql_client() {
  if need mysql && need mysqladmin; then
    return
  fi

  case "$(detect_pkg_mgr)" in
    apt)
      if ! pkg_install_best_effort percona-server-client mysql-client default-mysql-client; then
        echo "failed to install a MySQL client package" >&2
        exit 1
      fi
      ;;
    dnf|yum)
      if ! pkg_install_best_effort percona-server-client mysql mysql-community-client; then
        echo "failed to install a MySQL client package" >&2
        exit 1
      fi
      ;;
  esac
}
