# Changelog

## 1.1.0

- Renamed from `loki_journal` ("Loki Journal Shipper") to `ha_alloy` ("HA Alloy"): it runs Grafana Alloy.
- First release from the public app repository, as a prebuilt multi-arch image
  (`ghcr.io/jimmyhideous/app-ha-alloy`) for `amd64` and `aarch64`.
- Add an AppArmor profile: Alloy runs in its own child profile limited to the journal, its config, `/data` and
  TCP/UDP networking.
- Install Grafana Alloy 1.21.2 from the `.deb` attached to the GitHub release, checked against the release's
  `SHA256SUMS`, so Renovate can track new Alloy releases.
- The default `loki_url` is now a placeholder (`http://loki:3100/loki/api/v1/push`). Set it to your own Loki
  server.

## 1.0.3

- `app` is the container name again, exactly as Docker/Supervisor show it (`app_a0d7b954_ssh`,
  `hassio_supervisor`, `homeassistant`). The 1.0.2 renaming is reverted.

## 1.0.2

- Container lines without a level of their own get `level="stderr"` / `"stdout"` instead of the journal's
  `error` / `info`: Docker maps the output stream, not the severity, and many apps log normal output to stderr.
- Core and Supervisor levels are now spelled like the journal's own (`error`, `critical`, `warning`, ...).
- Friendly `app` names: the store-repository prefix is dropped (`app_a0d7b954_ssh` → `ssh`,
  `app_core_mosquitto` → `mosquitto`), `hassio_<x>` → `<x>`, and `homeassistant` → `core`.

## 1.0.1

- Read the host journal from `/var/log/journal` explicitly. The app container has no `/etc/machine-id`, so the
  default local-journal lookup found nothing and no lines were shipped.
- Pin the Alloy apt package as `1.21.2-1` (the Debian package revision), and drop the deprecated `build.yaml`:
  the base image is now the `BUILD_FROM` default in the Dockerfile.

## 1.0.0

- First release: Grafana Alloy 1.21.2 reads the Home Assistant OS host journal and pushes it to Loki.
- Labels: `job="journal"`, `host`, `app` (container name or syslog identifier), `unit`, `level`.
- Core and Supervisor lines take their level from the log line itself.
- Query strings and URL user info are removed from every line before it is sent.
