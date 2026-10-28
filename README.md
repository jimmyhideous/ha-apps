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

- `main` only changes through pull requests. Every change goes on a branch and is merged by pull request;
  direct pushes, force pushes and deleting `main` are blocked.
- On a pull request, `Lint` checks every app and `Builder` builds the images of the apps the PR changes for
  every architecture, without publishing them. Before those builds, `Smoke test` builds the amd64 image and
  runs the app's `tests/smoke.sh`: for `ha_alloy` it starts Loki and the app under its AppArmor profile with
  the runner's journal mounted, writes a marker line to the journal and passes when Loki returns it. `Lint status` and `Builder status` sum these up and must pass
  before a pull request can merge.
- Auto-merge is enabled: a pull request set to auto-merge merges as soon as `Lint status` and
  `Builder status` pass.
- Merging to `main` builds the changed apps again and publishes them to GHCR as
  `ghcr.io/jimmyhideous/app-<slug>`, tagged with the app's `version` and `latest`. A version that already exists
  in the registry is skipped, so bump `version` and add a changelog entry for every change that should reach
  users. After publishing, `Verify published image` checks that the version's manifest lists every
  architecture and runs `alloy --version` in the amd64 image.
- Renovate opens pull requests for new Grafana Alloy releases and GitHub Actions updates. On an Alloy pull
  request, the `Renovate version bump` workflow commits a patch `version` bump and a changelog entry to the
  pull request's branch. Renovate merges minor and patch Alloy updates once the checks pass; other updates are
  merged by hand.

Apps documentation: <https://contributors.home-assistant.io/apps/>

[aarch64-shield]: https://img.shields.io/badge/aarch64-yes-green.svg
[amd64-shield]: https://img.shields.io/badge/amd64-yes-green.svg
