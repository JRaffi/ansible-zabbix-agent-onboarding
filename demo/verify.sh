#!/usr/bin/env bash
# Prove the run actually worked: both hosts exist, both are PSK encrypted,
# and Zabbix has seen encrypted data arrive from them.
set -euo pipefail

API="http://localhost:8080/api_jsonrpc.php"
EXPECTED="ubuntu-target debian-target"

api() {
  curl -s -X POST "$API" -H 'Content-Type: application/json' \
       ${TOKEN:+-H "Authorization: Bearer $TOKEN"} -d "$1"
}

TOKEN=$(api '{"jsonrpc":"2.0","method":"user.login","params":{"username":"Admin","password":"zabbix"},"id":1}' \
        | sed -n 's/.*"result":"\([^"]*\)".*/\1/p' || true)
[ -n "$TOKEN" ] || { echo "FAIL: cannot log in to the Zabbix API"; exit 1; }

echo "Waiting for the first encrypted check to arrive (up to 3 minutes)"
for i in $(seq 1 36); do
  hosts=$(api '{"jsonrpc":"2.0","method":"host.get","params":{"output":["host","active_available","tls_connect"]},"id":1}')
  ready=true
  for h in $EXPECTED; do
    # the host must exist, use PSK (tls_connect 2) and have reported in (active_available 1)
    echo "$hosts" | tr '{' '\n' | grep -q "\"host\":\"$h\".*\"tls_connect\":\"2\".*\"active_available\":\"1\"" || ready=false
  done
  $ready && break
  printf '  waiting (%s/36)\r' "$i"
  sleep 5
done
printf '\r%-40s\r' ''    # clear the progress line

fail=0
for h in $EXPECTED; do
  line=$(echo "$hosts" | tr '{' '\n' | grep "\"host\":\"$h\"" || true)
  if [ -z "$line" ]; then
    echo "FAIL  $h  was not created in Zabbix"; fail=1; continue
  fi
  case "$line" in
    *'"tls_connect":"2"'*) enc="PSK" ;;
    *) enc="UNENCRYPTED"; fail=1 ;;
  esac
  case "$line" in
    *'"active_available":"1"'*) act="data arriving" ;;
    *) act="no data yet"; fail=1 ;;
  esac
  printf 'OK    %-14s %s, %s\n' "$h" "$enc" "$act"
done

[ "$fail" -eq 0 ] || { echo; echo "Verification failed."; exit 1; }
echo
echo "Verified: both hosts registered, PSK encrypted, sending data."
