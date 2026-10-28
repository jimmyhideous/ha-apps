# Changelog

## 1.2.2

- Alloy temp files in `/data/alloy/tmp`; no AppArmor denials on position saves.

## 1.2.1

- Ingress entry read with `bashio::app.ingress_entry`.

## 1.2.0

- Config folder `/config` (`addon_config`) with `config_mode`: `builtin`, `merged` (default), `custom`.
- Alloy UI through Ingress (nginx proxy, Supervisor address only).
- Options `log_level`, `exclude`, `memory_limit`.
- Loki options `bearer_token`, `basic_auth_username`, `basic_auth_password`, `tenant_id`,
  `tls_insecure_skip_verify`, `ca_file`.

## 1.1.0

- App `ha_alloy` (HA Alloy), multi-arch image `ghcr.io/jimmyhideous/app-ha-alloy` for `amd64` and `aarch64`.
- AppArmor profile with an Alloy child profile.
- Grafana Alloy 1.21.2 from the release `.deb`, checked against `SHA256SUMS`.
- Placeholder default `loki_url`.

## 1.0.x

- Journal to Loki with labels `job`, `host`, `app`, `unit`, `level`; query strings and URL user info removed.
