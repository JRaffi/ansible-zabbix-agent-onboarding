# ansible-zabbix-agent-onboarding

[![demo](https://github.com/JRaffi/ansible-zabbix-agent-onboarding/actions/workflows/demo.yml/badge.svg)](https://github.com/JRaffi/ansible-zabbix-agent-onboarding/actions/workflows/demo.yml)
[![License](https://img.shields.io/badge/License-MIT--0-brightgreen)](LICENSE)
[![Zabbix](https://img.shields.io/badge/Zabbix-7.4-D40000?logo=zabbix&logoColor=white)](https://www.zabbix.com/)
[![Ansible](https://img.shields.io/badge/ansible--core-no%20collections-EE0000?logo=ansible&logoColor=white)](https://docs.ansible.com/)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04-E95420?logo=ubuntu&logoColor=white)](https://ubuntu.com/)
[![Debian](https://img.shields.io/badge/Debian-12-A81D33?logo=debian&logoColor=white)](https://www.debian.org/)
![Architecture](https://img.shields.io/badge/arch-amd64%20%7C%20arm64-lightgrey)

Installing the agent is the easy half. The other half — creating the host in
Zabbix, with the right groups, templates, a PSK and a proxy group — is where
people fall back to clicking through the frontend. This playbook does both in
one pass, and running it twice changes nothing.

It talks to the Zabbix JSON-RPC API directly. No `community.zabbix`, no
`jmespath`, no collection requirements file: a bare `ansible-core` install is
enough.

```bash
make demo     # throwaway Zabbix 7.4 + two hosts, everything in containers
```

## What one run does

```
   Ansible controller                    target host                  Zabbix
          |                                   |                          |
          |-- apt: zabbix-release, agent2 --->|                          |
          |                                   |                          |
          |-- read PSK, or generate one ----->| /etc/zabbix/*.psk (0400) |
          |     (never overwrites an existing secret)                    |
          |                                   |                          |
          |-- template + validate config ---->| zabbix_agent2 -c ... -T  |
          |-- systemd: enable + start ------->|                          |
          |                                   |                          |
          |-- hostgroup.get / template.get / proxygroup.get ------------>|
          |-- host.get: does it exist? --------------------------------->|
          |-- host.create  or  host.update ---------------------------- >|
          |     name, groups, templates, interface, proxy group, PSK     |
          |                                   |                          |
          |                                   |<== encrypted checks ====>|
```

The host is created under `ansible_fqdn` in lowercase, and the agent derives
the same name with `HostnameItem=system.hostname[fqdn,lower]`. That match is
what makes active checks arrive under a name Zabbix recognises — get it wrong
and the agent silently reports to nobody.

## Try it without touching a server

The demo needs Docker and nothing else. Ansible runs in a container too.

```bash
git clone https://github.com/JRaffi/ansible-zabbix-agent-onboarding
cd ansible-zabbix-agent-onboarding
make demo
```

It builds a Zabbix 7.4 stack, boots one Ubuntu 24.04 and one Debian 12
container with **real systemd**, runs the playbook against both — and then runs
it a second time to show that nothing changes. Finally it verifies the result
against the API — both hosts present, both on PSK, both actually sending data —
so a green run means it worked, not that it finished. The same job runs in CI
on every push.

Afterwards:

| | |
|---|---|
| Frontend | <http://localhost:8080> |
| Login | `Admin` / `zabbix` |
| Look at | *Data collection → Hosts* — both hosts, both encrypted |
| Re-check | `make verify` |
| Shell | `make demo-shell` |
| Clean up | `make demo-down` (removes the volumes too) |

The targets are not stand-ins: they run systemd as PID 1, so the playbook uses
the same `systemd` module, the same `apt`, the same sshd as on a real machine.

## Use it for real

**1. Get an API token.** In Zabbix: *Users → API tokens → Create API token*.
The user needs write access to the host groups you deploy into.

```bash
export ZABBIX_API_URL=https://zabbix.example.com
export ZABBIX_API_TOKEN=xxxxxxxxxxxx
```

`group_vars/all.yml` reads both from the environment, so no secret has to be
committed. Putting them in the file and encrypting it with `ansible-vault`
works just as well.

**2. Point it at your Zabbix.** In `group_vars/all.yml`:

```yaml
zabbix_servers:
  - zbx-proxy01.example.com
  - zbx-proxy02.example.com
zabbix_host_groups:
  - "Linux servers"
zabbix_templates:
  - "Linux by Zabbix agent active"
```

Groups and templates must already exist — the playbook looks them up by name
and tells you exactly which one is missing rather than creating something you
did not ask for.

**3. List your hosts** in `inventory.ini`, or keep using the inventory you
already have:

```bash
ansible-playbook -i /srv/ansible/inventory.ini install_agent.yml
```

**4. Run it.**

```bash
ansible-playbook install_agent.yml               # everything
ansible-playbook install_agent.yml -l web01      # a single host
ansible-playbook update_config.yml               # config only, no API calls
```

## Settings

Everything lives in `group_vars/all.yml`.

| Variable | Default | What it does |
|---|---|---|
| `zabbix_api_url` | `$ZABBIX_API_URL` | Frontend URL. `/api_jsonrpc.php` is appended. |
| `zabbix_api_token` | `$ZABBIX_API_TOKEN` | API token, sent as a bearer token. |
| `zabbix_api_validate_certs` | `true` | Set to `false` only for a lab with a self-signed certificate. |
| `zabbix_release` | `7.4` | Which Zabbix repository to add. |
| `zabbix_servers` | `[zabbix.example.com]` | Servers or proxies the agent talks to. |
| `zabbix_server_passive` | derived | Who may query the agent. Overridden to `127.0.0.1` for the `zabbix_infra` group. |
| `zabbix_host_groups` | `[Linux servers]` | Must exist in Zabbix. |
| `zabbix_templates` | `[Linux by Zabbix agent active]` | Must exist in Zabbix. |
| `zabbix_proxy_group` | `""` | Empty means monitored by the server. See below. |
| `zabbix_use_ip` | `false` | Agent interface by DNS name, or by IP. |
| `zabbix_tls_psk` | `true` | Encrypt both directions with a pre-shared key. |
| `zabbix_show_psk` | `false` | Print the PSK. Off, because CI logs are forever. |
| `zabbix_allow_keys` | 2 update checks | `system.run[]` whitelist. `[]` deploys none. |
| `zabbix_apt_proxy` | `""` | HTTP proxy, used only to fetch the Zabbix repository package. |
| `zabbix_api_debug` | `false` | Show what the API answered. See *Troubleshooting*. |

Hosts that run Zabbix themselves belong in the `zabbix_infra` inventory group —
`group_vars/zabbix_infra.yml` restricts their passive checks to `127.0.0.1`.
That is deliberately a group and not a `hostname contains "zbx"` guess: the
rule is visible in the inventory instead of buried in a template.

## Why no collection

`community.zabbix` is the obvious choice and this playbook still does not use
it. Three reasons, in order of how much they hurt:

- **It lags behind Zabbix releases.** Proxy groups arrived in Zabbix 7.0; the
  module support came much later. When you need a new API field, `uri` has it
  the day Zabbix ships it.
- **It is one more thing to install and pin** on every controller and in CI,
  along with `jmespath` for `json_query`. This repository runs on `ansible-core`
  as installed.
- **You cannot see what it sends.** When Zabbix rejects a host, the JSON body
  in front of you is the whole story — with `-e zabbix_api_debug=true` you read
  the error verbatim instead of guessing at a module abstraction.

The cost is honest: you write the JSON-RPC calls yourself. They are about ten
lines each, and `module_defaults` at the top of the play carries the repeated
headers so each call stays readable.

## Proxy groups

A *proxy group* (Zabbix 7.0+) is not a proxy. It is a set of proxies that share
the load and fail over between themselves; a host is assigned to the group, and
Zabbix picks which proxy actually polls it.

```yaml
zabbix_proxy_group: "dc1-linux-proxies"     # exactly as it appears in Zabbix
```

This sets `monitored_by: 2` plus `proxy_groupid`. Left empty, the host gets
`monitored_by: 0` and is polled by the server itself. The name must match
character for character — the playbook aborts if the group is not found rather
than quietly creating a server-monitored host. To check what exists:

```bash
curl -s -X POST "$ZABBIX_API_URL/api_jsonrpc.php" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ZABBIX_API_TOKEN" \
  -d '{"jsonrpc":"2.0","method":"proxygroup.get","params":{"output":["name"]},"id":1}'
```

## The PSK, and why re-running is safe

TLS-PSK is on by default. On first contact the playbook generates 32 random
bytes, stores them in `/etc/zabbix/zabbix_agent2.psk` as `0400 zabbix:zabbix`,
and hands the same value to Zabbix through the API — so both ends are
configured in one step, with no copy-and-paste through a ticket.

On every later run it **reads the existing file** instead of generating a new
secret. That is the difference between a playbook you can put in a cron job and
one that breaks monitoring every time it runs: a fresh PSK on the agent that
Zabbix does not know means the host goes quiet, and the graph gap is the first
thing anyone notices.

The identity is `<fqdn>.agent`, derived, not stored anywhere.

## Troubleshooting

**A task shows `censored` instead of output.** The API tasks carry the token
and the PSK, so their output is hidden by default. If Zabbix rejects a host you
still get its message verbatim — the failure is reported by a separate task
that prints only the error. For the full request and response:

```bash
ansible-playbook install_agent.yml -l web01 -e zabbix_api_debug=true
```

Only do that on a host you are actively debugging — the output contains
secrets.

**`Host group(s) not found` / `Template(s) not found`.** The name must match
Zabbix exactly, including case and spaces. The error lists what was missing.

**The config fails to deploy.** The template is validated with
`zabbix_agent2 -c %s -T` before it replaces the live file, so a broken template
never reaches a running agent. The error message is the agent's own.

**A single host fails while the rest succeed.** Zabbix takes database locks
while writing a host, so parallel `host.create` calls can collide. The write
task carries `throttle: 1` and is retried three times, which makes the rollout
safe at any `--forks` — only that one API call is serialised, the package
install and configuration still run on all hosts at once.

**The host appears but stays grey.** Active checks need the agent to reach the
server on 10051, and the name Zabbix knows must equal what the agent sends.
Check with `zabbix_agent2 -c /etc/zabbix/zabbix_agent2.conf -p | head`.

## What is in here

```
install_agent.yml          install, configure, register - the whole job
update_config.yml          re-template the config only, no API, no PSK
group_vars/all.yml         every setting, commented
group_vars/zabbix_infra.yml  hosts that run Zabbix themselves
templates/                 agent config and the AllowKeys whitelist
inventory.ini              example inventory
demo/                      the throwaway lab behind `make demo`
demo/verify.sh             asks Zabbix whether it really worked
.github/workflows/demo.yml CI: runs the lab on every push
```

Tested on Ubuntu 24.04 and Debian 12, against Zabbix 7.4, on amd64 and arm64.

## Related

- [zabbix-the-hard-way](https://github.com/JRaffi/zabbix-the-hard-way) — build
  the server side by hand, one component per container. This repository picks
  up where that one leaves off.
