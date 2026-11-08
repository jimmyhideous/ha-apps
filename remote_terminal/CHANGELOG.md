# Changelog

## 1.1.1

- `packages` accepts capitalized names and installs them lowercase.
- When the SSH login fails, the panel shows the app's public key and where to add it, and waits for Enter.

## 1.1.0

- Option `packages`: Debian packages the app installs on the host at start, if missing (apt, passwordless sudo).
- Option `env_vars`: environment variables for the terminal's shell on the host.

## 1.0.0

- Web terminal through Ingress (ttyd) that opens an SSH session on a configured host with its own key.
