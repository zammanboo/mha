-- Run on the current primary.
-- Replace host ranges and passwords before use.

CREATE USER IF NOT EXISTS 'repl'@'10.0.0.%'
  IDENTIFIED BY 'CHANGE_ME_REPL_PASSWORD'
  REQUIRE SSL;
GRANT REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'repl'@'10.0.0.%';

CREATE USER IF NOT EXISTS 'orchestrator'@'10.0.0.%'
  IDENTIFIED BY 'CHANGE_ME_ORCH_PASSWORD'
  REQUIRE SSL;
GRANT SUPER, PROCESS, RELOAD, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'orchestrator'@'10.0.0.%';

CREATE USER IF NOT EXISTS 'proxysql_monitor'@'10.0.0.%'
  IDENTIFIED BY 'CHANGE_ME_MONITOR_PASSWORD'
  REQUIRE SSL;
GRANT USAGE, REPLICATION CLIENT ON *.* TO 'proxysql_monitor'@'10.0.0.%';

-- Create your application user on MySQL too. ProxySQL authenticates the frontend,
-- then connects to MySQL with the same username/password unless configured otherwise.
CREATE USER IF NOT EXISTS 'app'@'10.0.0.%'
  IDENTIFIED BY 'CHANGE_ME_APP_PASSWORD'
  REQUIRE SSL;
-- Example only. Replace with least-privilege grants for your schema.
-- GRANT SELECT, INSERT, UPDATE, DELETE, EXECUTE ON appdb.* TO 'app'@'10.0.0.%';

FLUSH PRIVILEGES;
