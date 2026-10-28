# herdr-setup

Installs Tinoco's Herdr setup on a new machine: the same plugins at the same commits, the
Herdr config (theme, sidebar quota rows, keybindings), the Hermes agent-detection override,
and the Hermes ↔ Herdr integration.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/TinocoAI/herdr-setup/main/install.sh | bash
```

or

```bash
git clone https://github.com/TinocoAI/herdr-setup && cd herdr-setup && ./install.sh
```

You can run it again safely. Plugins already installed from the right source and commit
are skipped. Options:

| option | effect |
| --- | --- |
| `--no-config` | keep the current `~/.config/herdr/config.toml` (by default it is backed up and replaced) |
| `--no-hermes` | skip the Hermes-side plugins and config |
| `--force` | reinstall every plugin |

Requirements: `herdr` (tested with 0.9.5), `git`, `python3`, a Rust toolchain (`cargo`), and
`bun` or `node` for live-sync-panes. Behind a TLS-intercepting proxy (Netskope), the script
uses `$SSL_CERT_FILE` or `~/.hermes/ssl/custom_bundle.pem` for cargo, git and node.

After installing, restart any Hermes sessions already running in Herdr panes.

## What gets installed

| plugin | source | ref |
| --- | --- | --- |
| herdr-agent-quota | [TinocoAI/herdr-agent-quota](https://github.com/TinocoAI/herdr-agent-quota) | `hermes-provider` |
| live-sync-panes | [TinocoAI/live-sync-panes](https://github.com/TinocoAI/live-sync-panes) | `tinoco` |
| mirror | [nikok6/herdr-mirror](https://github.com/nikok6/herdr-mirror) (unmodified upstream) | `195398c` |
| herdr-pane-labels | [TinocoAI/herdr-pane-labels](https://github.com/TinocoAI/herdr-pane-labels) | `main` |
| herdr-remote-bridge | [TinocoAI/herdr-remote-bridge](https://github.com/TinocoAI/herdr-remote-bridge) | `main` |
| scp-explorer | [TinocoAI/scp-explorer](https://github.com/TinocoAI/scp-explorer) | `main` |

- **Herdr config:** `herdr/config.toml` goes to `~/.config/herdr/config.toml`. It sets the
  gruvbox theme, the per-agent sidebar quota rows, and keybindings for live-sync, mirror,
  scp-explorer, quota refresh and remote-bridge.
- **Agent-detection override:** `~/.config/herdr/agent-detection/hermes.toml`, taken from
  `herdr-agent-quota/hermes-integration/`. Without it, Herdr shows Hermes 0.22 classic-CLI
  panes as idle while they work (herdrdev/herdr#5336).
- **Hermes side** (when `hermes` is on PATH):
  - the `herdr-agent-state` and `hermes-proctitle` Hermes plugins, installed into
    `~/.hermes/plugins/` and enabled;
  - `terminal.client_env_passthrough` set for the `HERDR_*` variables.

  See `hermes-integration/README.md` in herdr-agent-quota for why each piece is needed.

## Updating

Change the plugin repo, push, then run `./install.sh` again on each machine. A plugin is
reinstalled when its branch has moved to a new commit. To pin a different ref, edit the
`PLUGINS` list in `install.sh`.
