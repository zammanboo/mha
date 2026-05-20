#!/usr/bin/env python3
"""Orchestrator hook that updates ProxySQL hostgroups after promotion.

Requires PyMySQL:
  python3 -m pip install -r requirements.txt

Phases:
  pre      — mark failed host OFFLINE_SOFT before promotion (unplanned failover)
  post     — promote successor as writer, keep old writer OFFLINE_SOFT in reader
             group (unplanned failover; old master may be dead)
  graceful — same routing change but old writer is set ONLINE in reader group
             (graceful switchover; old master is healthy and will rejoin as replica)

Arguments are read from environment variables set by Orchestrator:
  FAILED_HOST, FAILED_PORT, SUCCESSOR_HOST, SUCCESSOR_PORT
"""

from __future__ import annotations

import logging
import os
import re
import sys

try:
    import pymysql
except ImportError as exc:
    raise SystemExit("PyMySQL is required. Install with: python3 -m pip install pymysql") from exc

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    stream=sys.stderr,
)
logger = logging.getLogger(__name__)

_HOSTNAME_RE = re.compile(r"^[A-Za-z0-9._-]{1,253}$")


def require_host(value: str, name: str) -> str:
    if not value:
        raise SystemExit(f"{name} env var is required")
    return validate_host(value, name)


def validate_host(value: str, name: str) -> str:
    if not _HOSTNAME_RE.match(value):
        raise SystemExit(f"invalid {name}: {value!r}")
    return value


def env_int(name: str, default: int) -> int:
    value = os.getenv(name)
    if value is None or value == "":
        return default
    try:
        return int(value)
    except ValueError:
        raise SystemExit(f"env var {name}={value!r} is not a valid integer")


def connect():
    return pymysql.connect(
        host=os.getenv("PROXYSQL_ADMIN_HOST", "127.0.0.1"),
        port=env_int("PROXYSQL_ADMIN_PORT", 6032),
        user=os.getenv("PROXYSQL_ADMIN_USER", "admin"),
        password=os.getenv("PROXYSQL_ADMIN_PASSWORD", "admin"),
        autocommit=True,
        charset="utf8mb4",
        cursorclass=pymysql.cursors.DictCursor,
    )


def execute(cur, sql: str, args=()):
    cur.execute(sql, args)


def load_and_save(cur):
    for statement in (
        "LOAD MYSQL SERVERS TO RUNTIME",
        "SAVE MYSQL SERVERS TO DISK",
    ):
        execute(cur, statement)


def pre_failover(cur, failed_host: str, failed_port: int):
    logger.info("pre_failover: marking %s:%d OFFLINE_SOFT", failed_host, failed_port)
    execute(
        cur,
        "UPDATE mysql_servers SET status = 'OFFLINE_SOFT' WHERE hostname = %s AND port = %s",
        (failed_host, failed_port),
    )
    load_and_save(cur)
    logger.info("pre_failover: done")


def _promote_successor(cur, failed_host: str, failed_port: int,
                       successor_host: str, successor_port: int,
                       old_writer_status: str):
    writer_hg = env_int("PROXYSQL_WRITER_HOSTGROUP", 10)
    reader_hg = env_int("PROXYSQL_READER_HOSTGROUP", 20)
    max_lag = env_int("PROXYSQL_MAX_REPLICATION_LAG", 5)

    execute(
        cur,
        "DELETE FROM mysql_servers WHERE hostgroup_id = %s AND NOT (hostname = %s AND port = %s)",
        (writer_hg, successor_host, successor_port),
    )
    execute(
        cur,
        """
        REPLACE INTO mysql_servers(hostgroup_id, hostname, port, status, max_replication_lag, comment)
        VALUES(%s, %s, %s, 'ONLINE', 0, 'writer promoted by orchestrator')
        """,
        (writer_hg, successor_host, successor_port),
    )
    execute(
        cur,
        """
        REPLACE INTO mysql_servers(hostgroup_id, hostname, port, status, max_replication_lag, comment)
        VALUES(%s, %s, %s, %s, %s, 'old writer after failover')
        """,
        (reader_hg, failed_host, failed_port, old_writer_status, max_lag),
    )
    load_and_save(cur)


def post_failover(cur, failed_host: str, failed_port: int,
                  successor_host: str, successor_port: int):
    logger.info(
        "post_failover: promoting %s:%d as writer; old writer %s:%d -> OFFLINE_SOFT in reader group",
        successor_host, successor_port, failed_host, failed_port,
    )
    _promote_successor(cur, failed_host, failed_port,
                       successor_host, successor_port,
                       old_writer_status="OFFLINE_SOFT")
    logger.info("post_failover: done")


def post_graceful_takeover(cur, failed_host: str, failed_port: int,
                           successor_host: str, successor_port: int):
    logger.info(
        "post_graceful: promoting %s:%d as writer; old writer %s:%d -> ONLINE in reader group",
        successor_host, successor_port, failed_host, failed_port,
    )
    _promote_successor(cur, failed_host, failed_port,
                       successor_host, successor_port,
                       old_writer_status="ONLINE")
    logger.info("post_graceful: done")


def parse_args(argv: list[str]) -> str:
    """Return the phase name from argv; remaining args come from env vars."""
    if len(argv) != 1 or argv[0] not in ("pre", "post", "graceful"):
        raise SystemExit("usage: proxysql_failover.py {pre|post|graceful}")
    return argv[0]


def main(argv: list[str]) -> int:
    phase = parse_args(argv)

    failed_host = require_host(os.environ.get("FAILED_HOST", ""), "FAILED_HOST")
    failed_port = env_int("FAILED_PORT", 3306)

    if phase in ("post", "graceful"):
        successor_host = require_host(
            os.environ.get("SUCCESSOR_HOST", ""), "SUCCESSOR_HOST"
        )
        successor_port = env_int("SUCCESSOR_PORT", 3306)
    else:
        successor_host = ""
        successor_port = 3306

    with connect() as conn:
        with conn.cursor() as cur:
            if phase == "pre":
                pre_failover(cur, failed_host, failed_port)
            elif phase == "post":
                post_failover(cur, failed_host, failed_port, successor_host, successor_port)
            else:
                post_graceful_takeover(cur, failed_host, failed_port, successor_host, successor_port)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
