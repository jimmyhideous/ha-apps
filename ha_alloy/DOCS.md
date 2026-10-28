# HA Alloy

This app runs Grafana Alloy, reads the Home Assistant OS host journal and pushes every line to a Loki
server. You can then search Core, Supervisor, app and OS logs in Grafana next to the rest of your logs.

## Installation

1. Add this repository to Home Assistant: **Settings > Apps > Install app**, then the menu in the top right,
   **Repositories**, and add `https://github.com/jimmyhideous/ha-apps`.
2. Install **HA Alloy**.
3. Set `loki_url` to your Loki server's push endpoint (see below) and start the app.
4. Check the app log: it prints the endpoint it ships to. In Grafana, query `{job="journal"}`.

## Permissions

The app only requests `journald: true`, which mounts the host journal read-only. It does **not** use the host
network or PID namespace, does not map `/config`, `/share` or `/ssl`, and has no Home Assistant or Supervisor API
access, so it cannot read `secrets.yaml`.

It also ships its own AppArmor profile. Grafana Alloy runs in a child profile that can only read the journal,
its own configuration and the system files Go needs (DNS, CA certificates), write its read position under
`/data`, and open TCP/UDP sockets.

## Configuration

```yaml
loki_url: "http://loki:3100/loki/api/v1/push"
host_label: "homeassistant"
max_age: "12h"
```

### Option: `loki_url`

The Loki push endpoint, ending in `/loki/api/v1/push`. The default `http://loki:3100/loki/api/v1/push` is only
a placeholder: replace it with the address of your own Loki server, for example
`http://192.0.2.10:3100/loki/api/v1/push` or `https://loki.example.com/loki/api/v1/push`.

The Loki server (or the proxy in front of it) must accept pushes from Home Assistant's IP address. This app sends
no credentials and no tenant header, so put an authenticating proxy in front of Loki if others can reach it.

### Option: `host_label`

The value of the `host` label on every line.

### Option: `max_age`

How far back to start reading on first start. After that, Alloy keeps its read position in `/data` and resumes
from there after restarts, so lines are not sent twice.

## Labels

| Label | Source |
|---|---|
| `job` | always `journal` |
| `host` | the `host_label` option |
| `app` | the container name as Docker/Supervisor show it (`homeassistant`, `hassio_supervisor`, `app_<repo>_<slug>`), else the syslog identifier of the host service |
| `unit` | the systemd unit, for host services |
| `level` | Core/Supervisor: from the line (`debug`, `info`, `warning`, `error`, `critical`). Other app containers: `stdout` or `stderr` (Docker only records the stream). Host services: the journal priority |

## Privacy

Before anything leaves Home Assistant, the app replaces URL query strings with `<query removed>` and URL
user info (`user:pass@`) with `<userinfo removed>`, because integrations sometimes log URLs that contain API keys.
