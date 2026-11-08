# HA Alloy

Grafana Alloy reads the Home Assistant OS host journal (Core, Supervisor, apps, OS) and pushes it to Grafana Loki.

## Installation

1. Add the repository `https://github.com/jimmyhideous/ha-apps` (**Settings > Apps > Install app >** menu **> Repositories**).
2. Install **HA Alloy**.
3. Set `loki_url` and start the app.
4. In Grafana, query `{job="journal"}`.

## Options

| Option | Default | Description |
|---|---|---|
| `loki_url` | `http://loki:3100/loki/api/v1/push` | Loki push endpoint (placeholder; set your own). |
| `host_label` | `homeassistant` | Value of the `host` label. |
| `max_age` | `12h` | Journal look-back on first start. The read position is kept in `/data`. |
| `config_mode` | `merged` | `builtin`, `merged` or `custom`, see [Config folder](#config-folder). |
| `log_level` | `warn` | Alloy log level: `error`, `warn`, `info`, `debug`. |
| `exclude` | unset | Regex. Drops lines whose `app` or `unit` label matches it. Fully anchored: `addon_.*`, not `addon_`. |
| `memory_limit` | unset | Go soft memory limit (`GOMEMLIMIT`), e.g. `128MiB`. |
| `bearer_token` | unset | `Authorization: Bearer` token for Loki. |
| `basic_auth_username` | unset | Basic auth username for Loki. |
| `basic_auth_password` | unset | Basic auth password for Loki. |
| `tenant_id` | unset | `X-Scope-OrgID` header for Loki. |
| `tls_insecure_skip_verify` | `false` | Skip TLS certificate verification. |
| `ca_file` | unset | CA certificate for Loki, a path under `/config`. |

`bearer_token` and basic auth are mutually exclusive. The Loki and auth options apply to the built-in writer
(`builtin` and `merged`).

## Config folder

`/addon_configs/<repository>_ha_alloy/` on the host is `/config` in the app. Alloy loads every `*.alloy` file in
it as one configuration together with the built-in pipeline.

| `config_mode` | Loaded |
|---|---|
| `builtin` | built-in pipeline only |
| `merged` | built-in pipeline and `/config/*.alloy` |
| `custom` | `/config/*.alloy` only |

- Component labels must be unique across all files. Built-in components: `loki.relabel "journal"`,
  `loki.relabel "exclude"`, `loki.source.journal "haos"`, `loki.process "haos"`, `loki.write "loki"`.
- In `merged` mode, forward to `loki.write.loki.receiver` to use the built-in writer.
- A `logging` block in a user file replaces the `log_level` option.
- Environment: `LOKI_URL`, `HOST_LABEL`, `MAX_AGE` (`sys.env("LOKI_URL")`).
- An empty folder gets `example.alloy.disabled` on start. Existing files are never changed.

## Alloy UI

**Open Web UI** on the app page shows the Alloy component graph and health through Ingress. Enable
**Show in sidebar** for a panel.

## Labels

| Label | Value |
|---|---|
| `job` | `journal` |
| `host` | `host_label` |
| `app` | container name (`homeassistant`, `hassio_supervisor`, `app_<repo>_<slug>`), else syslog identifier |
| `unit` | systemd unit (host services) |
| `level` | Core/Supervisor: level from the line. Other containers: `stdout`/`stderr`. Host services: journal priority |

URL query strings and URL user info are replaced with `<query removed>` / `<userinfo removed>` before shipping.

## Permissions

- `journald: true`: host journal, read-only.
- `addon_config`: the app's own config folder, read/write.
- Ingress: only the Supervisor (`172.30.32.2`) reaches the UI port.
- AppArmor: Alloy and nginx run in child profiles. No host network, no Home Assistant API, no `/config` of Home
  Assistant, no `/ssl`.
