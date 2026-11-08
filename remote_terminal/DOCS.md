# Remote Terminal

A [ttyd](https://github.com/tsl0922/ttyd) web terminal, served through Ingress, that runs `ssh` to one configured
host. Every open panel is its own SSH connection.

## Installation

1. Add the repository `https://github.com/jimmyhideous/ha-apps` (**Settings > Apps > Install app >** menu **> Repositories**).
2. Install **Remote Terminal**, set `host` and `username`, and start it.
3. The log and the **Remote Terminal** panel show the app's public key. Add it to `~/.ssh/authorized_keys` of that user on the host, ideally limited
   to Home Assistant's address: `from="<HA IP>" ssh-ed25519 AAAA... remote-terminal@homeassistant`.
4. Open **Remote Terminal** in the sidebar.

## Options

| Option | Default | Description |
|---|---|---|
| `host` | required | SSH server, a hostname or IP address. |
| `port` | `22` | SSH port. |
| `username` | required | User to log in as. |
| `tmux_session` | `web` | tmux session to attach or create on the host, on its own tmux server (`tmux -L <name>`); it needs `tmux` there. Empty: plain login shell. |
| `font_size` | `14` | Terminal font size in pixels. |
| `packages` | empty | Debian package names. At every start the app installs those missing on the host with `sudo -n apt-get install`; it needs apt and passwordless sudo for `username` there. A failure is logged as a warning and the terminal still starts. |
| `env_vars` | empty | `name` and `value` pairs set in the terminal's shell on the host. With tmux they go into the tmux server's global environment, so new sessions and windows get them; shells already running keep their old values. |

## Security

- Only Home Assistant administrators see the panel. The terminal port listens on localhost behind an nginx proxy
  that admits the Supervisor only; nothing is exposed on the network.
- The client key is created on first start in `/data/ssh` and is part of the app's backups. Uninstalling the app
  deletes it.
- The host key is trusted on first connection and pinned in `/data/ssh/known_hosts`. If the host's key changes,
  connections fail until the app is reinstalled.
- Connections arrive at the host from Home Assistant's own IP address.
