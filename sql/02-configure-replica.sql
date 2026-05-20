-- Run on the initial replica after it has been provisioned from the primary.
-- Replace host, password, and SSL settings before use.

STOP REPLICA;
RESET REPLICA ALL;

CHANGE REPLICATION SOURCE TO
  SOURCE_HOST = 'mysql-a',
  SOURCE_PORT = 3306,
  SOURCE_USER = 'repl',
  SOURCE_PASSWORD = 'CHANGE_ME_REPL_PASSWORD',
  SOURCE_AUTO_POSITION = 1,
  SOURCE_SSL = 1,
  GET_SOURCE_PUBLIC_KEY = 1;

START REPLICA;

SHOW REPLICA STATUS\G
