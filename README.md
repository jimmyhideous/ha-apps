# jimmyhideous Home Assistant apps

Home Assistant app repository.

[![Open your Home Assistant instance and show the app store with a specific repository URL pre-filled.](https://my.home-assistant.io/badges/supervisor_store.svg)](https://my.home-assistant.io/redirect/supervisor_store/?repository_url=https%3A%2F%2Fgithub.com%2Fjimmyhideous%2Fha-apps)

To add it by hand: **Settings > Apps > Install app**, the menu in the top right, **Repositories**, then add
`https://github.com/jimmyhideous/ha-apps`.

## Apps

This repository contains the following apps

### [HA Alloy](./ha_alloy)

![Supports aarch64 Architecture][aarch64-shield]
![Supports amd64 Architecture][amd64-shield]

_Ships the Home Assistant OS journal (Core, Supervisor, every app and the OS) to Grafana Loki with Grafana
Alloy. Needs only read access to the journal._

## Maintenance

- Images are built by GitHub Actions with the Home Assistant builder actions and published to GHCR as
  `ghcr.io/jimmyhideous/app-<slug>`, tagged with the app's `version`. A merge to `main` publishes a version
  once; a version that already exists in the registry is never pushed again, so bump `version` (and the
  changelog) for every change that should reach users.
- Renovate keeps Grafana Alloy and the GitHub Actions up to date. For Alloy updates, the `Renovate version
  bump` workflow bumps the app's patch version and adds a changelog entry to the Renovate pull request.

Apps documentation: <https://contributors.home-assistant.io/apps/>

[aarch64-shield]: https://img.shields.io/badge/aarch64-yes-green.svg
[amd64-shield]: https://img.shields.io/badge/amd64-yes-green.svg
