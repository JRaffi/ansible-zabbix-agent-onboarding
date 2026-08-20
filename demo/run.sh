#!/usr/bin/env bash
# Bring up the lab and run the playbook against it.
# Nothing is installed on your machine - everything happens in containers.
set -euo pipefail

cd "$(dirname "$0")"
COMPOSE="docker compose -f docker-compose.yml"
API="http://localhost:8080/api_jsonrpc.php"

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

say "Building and starting the lab (first run pulls a few images)"
$COMPOSE up -d --build

say "Waiting for the Zabbix frontend to answer (schema import takes a minute)"
for i in $(seq 1 120); do
  version=$(curl -s -m 5 -X POST "$API" \
      -H 'Content-Type: application/json' \
      -d '{"jsonrpc":"2.0","method":"apiinfo.version","params":{},"id":1}' \
    | sed -n 's/.*"result":"\([^"]*\)".*/\1/p' || true)
  if [ -n "${version:-}" ]; then
    printf '    Zabbix API %s is up\n' "$version"
    break
  fi
  printf '    still starting (%s/120)\r' "$i"
  sleep 5
done
if [ -z "${version:-}" ]; then
  echo "ERROR: the Zabbix API did not come up. Check: $COMPOSE logs zabbix-web" >&2
  exit 1
fi

say "Logging in as the default Admin user to get an API token"
token=$(curl -s -X POST "$API" \
    -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","method":"user.login","params":{"username":"Admin","password":"zabbix"},"id":1}' \
  | sed -n 's/.*"result":"\([^"]*\)".*/\1/p' || true)
if [ -z "$token" ]; then
  echo "ERROR: could not log in to the Zabbix API." >&2
  exit 1
fi
printf '    got a session token (%s...)\n' "${token:0:8}"

say "Waiting for SSH on the target containers"
for i in $(seq 1 30); do
  if $COMPOSE exec -T controller \
       ansible -i /repo/demo/inventory.ini all -m ping >/dev/null 2>&1; then
    printf '    both targets reachable\n'
    break
  fi
  printf '    waiting for sshd (%s/30)\r' "$i"
  sleep 3
done

say "Running install_agent.yml against ubuntu-target and debian-target"
$COMPOSE exec -T -e ZABBIX_API_TOKEN="$token" controller \
  ansible-playbook /repo/install_agent.yml -e @/repo/demo/demo-vars.yml "$@"

say "Running it a second time to prove it is idempotent"
$COMPOSE exec -T -e ZABBIX_API_TOKEN="$token" controller \
  ansible-playbook /repo/install_agent.yml -e @/repo/demo/demo-vars.yml "$@"

say "Checking what actually arrived in Zabbix"
bash ./verify.sh          # run.sh already cd-ed into demo/

cat <<MSG

Done. The two hosts are now in Zabbix, encrypted with a PSK each.

  Frontend   http://localhost:8080
  Login      Admin / zabbix
  Check      Data collection -> Hosts -> ubuntu-target / debian-target
             The lock icon in the Agent column turns green once the first
             encrypted check has arrived (up to a minute).

  Shell      docker compose -f demo/docker-compose.yml exec controller bash
  Tear down  make demo-down

MSG
