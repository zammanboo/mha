#!/usr/bin/env python3
"""Orchestrator hook that updates ProxySQL hostgroups after promotion.

Requires PyMySQL:
  python3 -m pip install -r requirements.txt
"""

from __future__ import annotations

import argparse
import os
import sys

try:
    import pymysql
except ImportError as exc:
    raise SystemExit("PyMySQL is required. Install with: python3 -m pip install pymysql") from exc


def env_int(name: str, default: int) -> int:
    value = os.getenv(name)
    return default if value is None or value == "" else int(value)


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
    execute(
        cur,
        "UPDATE mysql_servers SET status = 'OFFLINE_SOFT' WHERE hostname = %s AND port = %s",
        (failed_host, failed_port),
    )
    load_and_save(cur)


def post_failover(cur, failed_host: str, failed_port: int, successor_host: str, successor_port: int):
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
        VALUES(%s, %s, %s, 'OFFLINE_SOFT', %s, 'old writer after failover')
        """,
        (reader_hg, failed_host, failed_port, max_lag),
    )
    load_and_save(cur)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("phase", choices=("pre", "post"))
    parser.add_argument("--failed-host", required=True)
    parser.add_argument("--failed-port", type=int, default=3306)
    parser.add_argument("--successor-host", default="")
    parser.add_argument("--successor-port", type=int, default=3306)
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    with connect() as conn:
        with conn.cursor() as cur:
            if args.phase == "pre":
                pre_failover(cur, args.failed_host, args.failed_port)
            else:
                if not args.successor_host:
                    raise SystemExit("--successor-host is required for post phase")
                post_failover(
                    cur,
                    args.failed_host,
                    args.failed_port,
                    args.successor_host,
                    args.successor_port,
                )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
