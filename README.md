# Home Assistant apps

Home Assistant app repository.

[![Open your Home Assistant instance and show the app store with a specific repository URL pre-filled.](https://my.home-assistant.io/badges/supervisor_store.svg)](https://my.home-assistant.io/redirect/supervisor_store/?repository_url=https%3A%2F%2Fgithub.com%2Fjimmyhideous%2Fha-apps)

Manual: **Settings > Apps > Install app >** menu **> Repositories**, add `https://github.com/jimmyhideous/ha-apps`.

## Apps

| App | Description |
|---|---|
| [HA Alloy](./ha_alloy) | Ships the Home Assistant OS journal to Grafana Loki with Grafana Alloy. `aarch64`, `amd64`. |

## Maintenance

- `main` changes only through pull requests; direct pushes, force pushes and deletion are blocked.
- `Lint`: app linter on every app.
- `Builder`: on a pull request, `Smoke test` (amd64 image, `<app>/tests/smoke.sh`) and an unpublished build of
  each changed app for every architecture.
- `Lint status` and `Builder status` are required checks; auto-merge merges when both pass.
- On `main`, changed apps are published to `ghcr.io/jimmyhideous/app-<slug>` as `<version>` and `latest`;
  existing versions are skipped. `Verify published image` checks the manifest architectures and runs the amd64
  image.
- Every user-facing change bumps `version` and adds a `CHANGELOG.md` entry.
- Renovate updates Grafana Alloy, the base image, the smoke test images and GitHub Actions.
- `Renovate version bump` adds a patch `version` bump and changelog entry to Renovate's Alloy pull requests.
- Renovate auto-merges minor and patch updates of Alloy and of the smoke test images; other updates are merged by
  hand.

Apps documentation: <https://contributors.home-assistant.io/apps/>
