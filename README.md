# MySQL HA 구성안

이 저장소는 2대 MySQL 서버를 `primary -> replica` 구조로 운영하면서 MHA를 대체하기 위한 기본 템플릿입니다.

## 결론

Perl MHA를 새로 유지보수하는 대신 **Orchestrator + ProxySQL** 조합을 권장합니다.

- Orchestrator는 MySQL replication topology discovery, switchover, failover를 담당합니다.
- ProxySQL은 애플리케이션 접속 endpoint, writer/reader hostgroup routing, 장애조치 후 트래픽 전환을 담당합니다.
- 2026년 4월 ProxySQL 쪽이 Orchestrator 유지보수와 개발을 이어받겠다고 발표했고, Percona도 이 흐름을 확인했습니다.

참고:

- ProxySQL announcement: https://proxysql.com/blog/announcing-proxysql-takes-over-orchestrator/
- Percona note: https://www.percona.com/blog/orchestrators-next-chapter-what-it-means-for-percona-customers/
- Orchestrator repository: https://github.com/percona/orchestrator
- MySQL InnoDB Cluster 최소 3대 요구: https://dev.mysql.com/doc/refman/9.7/en/mysql-innodb-cluster-introduction.html
- ProxySQL failover FAQ: https://proxysql.com/documentation/frequently-asked-questions/

## 중요한 제약

2대만으로는 quorum 기반 HA가 아닙니다. 따라서 완전 자동 failover는 다음 위험을 가집니다.

- primary가 죽은 것처럼 보이지만 실제로 살아 있는 network partition 상황에서 split-brain 가능성
- async replication 지연 중 primary crash가 나면 일부 transaction 유실 가능성
- Orchestrator 자체를 1대로만 두면 관리 plane이 SPOF

운영에서 가능한 최소 보강은 다음입니다.

- GTID replication 사용
- `read_only`/`super_read_only` 강제
- semi-sync replication 활성화 검토
- fencing 또는 VIP 회수 절차 마련
- 장애조치 자동화 전 `FailureDetectionPeriodBlockMinutes`, promotion delay, lag threshold를 보수적으로 설정

가장 안전한 방향은 DB 3대 이상으로 MySQL InnoDB Cluster 또는 Orchestrator Raft 구성을 쓰는 것입니다. 그래도 "DB 서버 2대" 제약이 고정이라면 이 저장소의 구성을 사용하세요.

## 권장 버전

2026-05-20 기준 MySQL 최신 LTS 라인은 9.7 LTS입니다. 다만 새 LTS로 막 올라간 시점이므로 운영 안정성을 더 중시하면 MySQL 8.4 LTS를 먼저 선택하고, 애플리케이션 호환성 검증 후 9.7 LTS로 올리는 쪽이 보수적입니다.

이 템플릿은 MySQL 8.4/9.7 계열의 `SOURCE`/`REPLICA` 용어와 GTID replication을 기준으로 작성했습니다.

## 파일 구성

- `mysql/primary.cnf`: primary 서버용 MySQL 설정
- `mysql/replica.cnf`: replica 서버용 MySQL 설정
- `sql/01-create-ha-users.sql`: replication, Orchestrator, ProxySQL monitor 사용자 생성
- `sql/02-configure-replica.sql`: GTID replica 연결 예시
- `proxysql/bootstrap.sql`: ProxySQL hostgroup/user/query rule 초기화
- `orchestrator/orchestrator.conf.json`: Orchestrator 기본 설정 템플릿. `__BASE_DIR__` placeholder는 배포 시 실제 값으로 치환됩니다.
- `env/mysql-ha.env.example`: 서버별 `BASE_DIR`, Percona repository, service name 예시
- `systemd/orchestrator.service`: 패키지가 service unit을 제공하지 않을 때 사용할 systemd 템플릿
- `scripts/common_install.sh`: Linux 패키지 매니저/Percona repository 공통 함수
- `scripts/register_base_dir.sh`: `/etc/mysql-ha.env`에 `BASE_DIR` 등록
- `scripts/install_mysql_node.sh`: Percona Server, XtraBackup, Toolkit, MySQL client 설치
- `scripts/install_proxy_vip.sh`: ProxySQL, keepalived, MySQL client, PyMySQL 설치
- `scripts/install_all.sh`: 한 서버에 MySQL, ProxySQL/VIP, Orchestrator를 모두 설치
- `scripts/install_orchestrator.sh`: Percona 패키지로 Orchestrator binary/client/service를 설치하는 도우미
- `scripts/deploy_configs.sh`: MySQL/keepalived/Orchestrator 설정과 hook 스크립트를 서버 경로에 배치
- `scripts/restart_services.sh`: 설정 변경 후 역할별 서비스 재시작
- `scripts/proxysql_failover.py`: Orchestrator hook에서 ProxySQL hostgroup을 갱신하는 Python 스크립트
- `scripts/check_proxysql.sh`: keepalived에서 호출하는 ProxySQL health check
- `scripts/preflight.sh`: 서버 준비 상태 점검 스크립트
- `keepalived/keepalived-primary.conf`, `keepalived/keepalived-replica.conf`: ProxySQL VIP를 쓸 때의 keepalived 예시

## 배치 예시

예시 IP는 반드시 환경에 맞게 바꾸세요.

- `mysql-a`: `10.0.0.11`, server_id `101`, 최초 primary
- `mysql-b`: `10.0.0.12`, server_id `102`, 최초 replica
- ProxySQL admin: `127.0.0.1:6032`
- ProxySQL service: `6033`
- VIP: `10.0.0.50`

## 설치 흐름

1. 두 서버에서 `BASE_DIR`를 등록합니다.
2. 두 서버에 MySQL LTS, ProxySQL, Orchestrator, keepalived를 설치합니다.
3. 서버 역할에 맞게 설정 파일을 배치합니다.
4. 설정 파일의 `CHANGE_ME_*`, hostname, VIP, interface 값을 수정합니다.
5. 두 MySQL 서버를 재시작합니다.
6. primary에서 `sql/01-create-ha-users.sql`을 환경에 맞게 수정 후 실행합니다.
7. replica 데이터를 백업/복구 또는 clone으로 primary와 맞춘 뒤 `sql/02-configure-replica.sql`을 실행합니다.
8. ProxySQL admin에서 `proxysql/bootstrap.sql`을 환경에 맞게 수정 후 실행합니다.
9. Orchestrator 서비스를 시작합니다.
10. Orchestrator에 두 노드를 discover 합니다.

```bash
orchestrator-client -c discover -i mysql-a:3306
orchestrator-client -c discover -i mysql-b:3306
orchestrator-client -c topology -i mysql-a:3306
```

### 필요한 패키지

이 저장소의 전체 구성에 필요한 패키지는 다음입니다.

| 역할 | 패키지 |
|---|---|
| MySQL 서버 | `percona-server-server` |
| 백업/초기 replica provision | `percona-xtrabackup-84` |
| 운영 점검 도구 | `percona-toolkit` |
| Orchestrator | `percona-orchestrator`, `percona-orchestrator-cli`, `percona-orchestrator-client` |
| ProxySQL | `proxysql2` |
| VIP | `keepalived` |
| MySQL CLI/health check | `percona-server-client` 또는 배포판의 MySQL client |
| Python hook | `python3`, `python3-pymysql` 또는 `PyMySQL` |
| repository bootstrap | `curl`, `ca-certificates`, `gnupg` |

Percona Distribution for MySQL 8.4 문서 기준으로 Orchestrator는 `percona-orchestrator percona-orchestrator-cli percona-orchestrator-client`, ProxySQL은 `proxysql2`, Percona Server는 `percona-server-server` 패키지로 설치합니다.

먼저 서버마다 런타임 파일을 둘 `BASE_DIR`를 등록합니다. 기본 예시는 `/opt/mysql-ha`이지만 원하는 절대경로를 사용할 수 있습니다.

```bash
sudo ./scripts/register_base_dir.sh /opt/mysql-ha
```

등록 결과는 `/etc/mysql-ha.env`에 저장됩니다.

```bash
BASE_DIR=/opt/mysql-ha
PERCONA_SETUP=pdps-84-lts
SERVICE_NAME=orchestrator
```

다른 env 파일을 사용해야 하면 `MYSQL_HA_ENV`로 지정합니다.

```bash
sudo MYSQL_HA_ENV=/etc/my-ha.env ./scripts/register_base_dir.sh /data/mysql-ha
```

두 DB 서버에 모든 구성요소를 같이 올리는 단순한 2대 구성이라면 다음을 실행합니다.

```bash
sudo ./scripts/install_all.sh
```

역할별로 나누어 설치하려면 다음을 사용합니다.

```bash
sudo ./scripts/install_mysql_node.sh
sudo ./scripts/install_proxy_vip.sh
sudo ./scripts/install_orchestrator.sh
```

설치 후 준비 상태를 확인합니다.

```bash
sudo ./scripts/preflight.sh
```

패키지 설치 후 서버 역할에 맞는 설정 파일을 배치합니다.

```bash
sudo ./scripts/deploy_configs.sh primary
sudo ./scripts/deploy_configs.sh replica
```

`deploy_configs.sh`는 다음 위치에 파일을 배치합니다.

| 대상 | 경로 |
|---|---|
| Orchestrator 설정 | `/etc/orchestrator.conf.json` |
| Orchestrator hook | `$BASE_DIR/scripts/proxysql_failover.py` |
| ProxySQL health check | `$BASE_DIR/scripts/check_proxysql.sh` |
| MySQL 설정 | `/etc/mysql/conf.d/mysql-ha.cnf` 또는 `/etc/my.cnf.d/mysql-ha.cnf` |
| keepalived 설정 | `/etc/keepalived/keepalived.conf` |

`orchestrator/orchestrator.conf.json`과 `keepalived/*.conf` 안의 `__BASE_DIR__`는 `deploy_configs.sh`가 서버 경로로 복사할 때 실제 `BASE_DIR` 값으로 치환합니다. Orchestrator와 keepalived 자체는 이 placeholder를 치환하지 않으므로, 반드시 `deploy_configs.sh`를 통해 배치하세요.

기존 파일은 기본적으로 덮어쓰지 않습니다. 덮어쓰려면 `FORCE=1`을 붙입니다.

```bash
sudo FORCE=1 ./scripts/deploy_configs.sh primary
```

설정 파일의 `CHANGE_ME_*`, hostname, VIP, interface 값을 수정한 뒤 필요한 서비스만 재시작합니다.

```bash
sudo ./scripts/restart_services.sh mysql
sudo ./scripts/restart_services.sh proxy
sudo ./scripts/restart_services.sh orchestrator
```

### Orchestrator 설치

`systemctl enable --now orchestrator`는 설치 명령이 아닙니다. 이 명령이 동작하려면 먼저 `orchestrator` binary와 `orchestrator.service`가 설치되어 있어야 합니다.

Percona 패키지를 사용할 수 있는 Linux 서버라면 이 저장소의 설치 스크립트를 사용할 수 있습니다.

```bash
sudo ./scripts/install_orchestrator.sh
```

이 스크립트가 하는 일은 다음과 같습니다.

- Percona repository 설정
- `percona-orchestrator`, `percona-orchestrator-cli`, `percona-orchestrator-client` 설치
- `/etc/orchestrator.conf.json`이 없으면 이 저장소의 템플릿을 `BASE_DIR` 값으로 렌더링해서 복사
- 패키지가 systemd unit을 제공하지 않으면 `systemd/orchestrator.service` 템플릿 등록
- `systemctl enable --now orchestrator` 실행

기본 repository setup 값은 `pdps-84-lts`입니다. 다른 Percona repository를 사용해야 하면 `/etc/mysql-ha.env`의 `PERCONA_SETUP`을 바꾸거나 환경변수로 넘깁니다.

```bash
sudo PERCONA_SETUP=pdps-84-lts ./scripts/install_orchestrator.sh
```

내부적으로는 Percona 공식 문서의 `percona-release enable pdps-84-lts` 방식을 사용합니다.

### Orchestrator 폴더의 의미

이 저장소의 `orchestrator/` 폴더는 Orchestrator 설치 디렉터리가 아닙니다. 여기에는 배포 전에 `/etc/orchestrator.conf.json`으로 렌더링할 설정 템플릿만 있습니다.

```bash
sudo ./scripts/deploy_configs.sh primary
sudo systemctl enable --now orchestrator
```

주의: `orchestrator/orchestrator.conf.json`을 직접 `cp`하면 `__BASE_DIR__` placeholder가 그대로 남습니다. `deploy_configs.sh` 또는 `install_orchestrator.sh`를 통해 배치하세요.

실제 실행 파일은 OS 패키지나 직접 빌드로 설치해야 합니다. 설치 후 보통 다음 중 하나가 보여야 합니다.

```bash
command -v orchestrator
command -v orchestrator-client
systemctl status orchestrator
```

### Orchestrator 서비스 위치

`systemctl enable --now orchestrator`가 동작하려면 systemd unit 파일이 먼저 있어야 합니다. 패키지로 설치하면 보통 패키지가 unit 파일을 같이 설치하지만, 직접 binary만 배치했다면 이 저장소의 템플릿을 사용하세요.

```bash
sudo useradd --system --home /var/lib/orchestrator --shell /usr/sbin/nologin orchestrator
sudo mkdir -p /var/lib/orchestrator
sudo chown orchestrator:orchestrator /var/lib/orchestrator
sudo cp systemd/orchestrator.service /etc/systemd/system/orchestrator.service
sudo systemctl daemon-reload
sudo systemctl enable --now orchestrator
```

템플릿은 Orchestrator binary가 `/usr/local/bin/orchestrator`에 있다고 가정합니다.

```ini
ExecStart=/usr/local/bin/orchestrator http
```

다른 위치에 설치했다면 먼저 실제 경로를 확인하고 service 파일의 `ExecStart`를 수정하세요.

```bash
command -v orchestrator
```

### `orchestrator-client`가 없을 때

`orchestrator-client`는 MySQL 기본 명령이 아니라 Orchestrator의 client wrapper입니다. 설치 방식에 따라 기본 PATH에 없거나, server 패키지만 설치되어 빠져 있을 수 있습니다.

먼저 위치를 확인합니다.

```bash
command -v orchestrator-client
command -v orchestrator
```

패키지로 설치했다면 다음 명령으로 포함 파일을 확인할 수 있습니다.

```bash
rpm -ql orchestrator orchestrator-client 2>/dev/null | grep orchestrator-client
dpkg -L orchestrator orchestrator-client 2>/dev/null | grep orchestrator-client
```

`orchestrator-client`가 없다면 Orchestrator HTTP API로 같은 작업을 실행할 수 있습니다.

```bash
curl -sf http://127.0.0.1:3000/api/discover/mysql-a/3306
curl -sf http://127.0.0.1:3000/api/discover/mysql-b/3306
curl -s http://127.0.0.1:3000/api/clusters
curl -s http://127.0.0.1:3000/api/all-instances
```

또는 Orchestrator binary가 CLI command mode를 지원하는 설치본이라면 다음처럼 실행합니다.

```bash
orchestrator -c discover -i mysql-a:3306
orchestrator -c topology -i mysql-a:3306
```

운영 자동화에서는 `orchestrator-client`에 의존하기보다 API endpoint를 명시적으로 호출하는 방식이 더 찾기 쉽습니다.

## VIP 실행 방법

VIP는 `keepalived` 데몬이 `/etc/keepalived/keepalived.conf`를 읽어서 실행합니다. 이 저장소의 `keepalived/*.conf` 파일은 배포용 템플릿입니다.

primary 서버:

```bash
sudo cp keepalived/keepalived-primary.conf /etc/keepalived/keepalived.conf
sudo systemctl enable --now keepalived
```

replica 서버:

```bash
sudo cp keepalived/keepalived-replica.conf /etc/keepalived/keepalived.conf
sudo systemctl enable --now keepalived
```

설정 전에 반드시 다음 값을 환경에 맞게 바꾸세요.

- `interface eth0`: 실제 NIC 이름
- `virtual_ipaddress`: 실제 사용할 VIP와 prefix
- `auth_pass CHANGE_ME`: 두 서버에서 동일한 VRRP 인증값

현재 예시 VIP는 `10.0.0.50/24`입니다.

```conf
virtual_ipaddress {
  10.0.0.50/24
}
```

동작 흐름은 다음과 같습니다.

```text
application -> VIP:6033 -> keepalived가 MASTER로 판단한 서버의 ProxySQL -> MySQL writer/reader hostgroup
```

VIP 상태 확인:

```bash
systemctl status keepalived
ip addr show
journalctl -u keepalived -f
```

ProxySQL health check는 `$BASE_DIR/scripts/check_proxysql.sh`가 수행합니다. 내부적으로 `mysqladmin --protocol=tcp -h 127.0.0.1 -P 6033 ping`을 호출하며, 이 check가 실패하면 keepalived priority가 내려가고 VIP가 반대편 서버로 이동합니다.

## 장애조치 테스트

처음부터 자동 failover를 켜지 말고, 먼저 graceful switchover를 검증하세요.

```bash
orchestrator-client -c graceful-master-takeover -i mysql-a:3306 -d mysql-b:3306
```

`orchestrator-client`가 없다면 같은 서버에서 Orchestrator binary로 시도합니다.

```bash
orchestrator -c graceful-master-takeover -i mysql-a:3306 -d mysql-b:3306
```

검증 항목:

- 새 primary의 `read_only = OFF`, `super_read_only = OFF`
- 이전 primary 또는 남은 replica의 `read_only = ON`, `super_read_only = ON`
- `SHOW REPLICA STATUS\G`에서 GTID auto-position 동작
- ProxySQL `mysql_servers`에서 writer hostgroup이 새 primary를 가리킴
- 애플리케이션 쓰기 트래픽이 VIP/ProxySQL을 통해 새 primary로 들어감

## Python HA 매니저를 새로 쓰지 않은 이유

이 요구사항에는 새 Python daemon보다 Orchestrator가 낫습니다. 장애 감지, topology 분석, GTID promotion, audit, hooks, UI/API 같은 실패하기 쉬운 부분이 이미 검증되어 있기 때문입니다.

이 저장소의 Python 코드는 HA brain이 아니라 Orchestrator hook 보조 도구입니다. 즉, 장애조치 판단은 Orchestrator에 맡기고 ProxySQL 반영만 Python으로 작고 명확하게 처리합니다.
