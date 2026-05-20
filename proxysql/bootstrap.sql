-- Run against ProxySQL admin, usually:
-- mysql -u admin -padmin -h 127.0.0.1 -P 6032 < proxysql/bootstrap.sql
--
-- Replace hostnames, passwords, and hostgroups before use.

DELETE FROM mysql_servers;
DELETE FROM mysql_replication_hostgroups;
DELETE FROM mysql_users WHERE username IN ('app', 'proxysql_monitor');
DELETE FROM mysql_query_rules;

-- Hostgroups:
-- 10 = writer, 20 = reader
INSERT INTO mysql_servers(hostgroup_id, hostname, port, status, max_replication_lag, comment) VALUES
  (10, 'mysql-a', 3306, 'ONLINE', 0, 'initial writer'),
  (20, 'mysql-b', 3306, 'ONLINE', 5, 'initial reader');

INSERT INTO mysql_replication_hostgroups(writer_hostgroup, reader_hostgroup, check_type, comment) VALUES
  (10, 20, 'read_only', 'mysql-ha');

SET mysql-monitor_username = 'proxysql_monitor';
SET mysql-monitor_password = 'CHANGE_ME_MONITOR_PASSWORD';
SET mysql-monitor_connect_interval = 2000;
SET mysql-monitor_ping_interval = 1000;
SET mysql-monitor_read_only_interval = 1000;
SET mysql-monitor_replication_lag_interval = 1000;

INSERT INTO mysql_users(username, password, default_hostgroup, transaction_persistent, active) VALUES
  ('app', 'CHANGE_ME_APP_PASSWORD', 10, 1, 1);

-- Keep locking reads and writes on the writer. Send simple SELECTs to readers.
INSERT INTO mysql_query_rules(rule_id, active, match_digest, destination_hostgroup, apply, comment) VALUES
  (100, 1, '^SELECT.*FOR UPDATE', 10, 1, 'locking reads go to writer'),
  (110, 1, '^SELECT', 20, 1, 'read traffic goes to readers');

LOAD MYSQL VARIABLES TO RUNTIME;
SAVE MYSQL VARIABLES TO DISK;
LOAD MYSQL SERVERS TO RUNTIME;
SAVE MYSQL SERVERS TO DISK;
LOAD MYSQL USERS TO RUNTIME;
SAVE MYSQL USERS TO DISK;
LOAD MYSQL QUERY RULES TO RUNTIME;
SAVE MYSQL QUERY RULES TO DISK;
