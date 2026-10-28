#!/usr/bin/env bash
# Reproduce Tinoco's Herdr setup on this machine: plugins (pinned), Herdr
# config, Hermes agent-detection override and the Hermes <-> Herdr integration.
#
#   curl -fsSL https://raw.githubusercontent.com/TinocoAI/herdr-setup/main/install.sh | bash
#   ./install.sh [--no-config] [--no-hermes] [--force]
#
# --no-config  keep the existing ~/.config/herdr/config.toml
# --no-hermes  skip the Hermes-side plugins/config
# --force      reinstall plugins even when already installed from the right source
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/TinocoAI/herdr-setup/main"
HERDR_CFG="${HERDR_CONFIG_DIR:-$HOME/.config/herdr}"
DO_CONFIG=1 DO_HERMES=1 FORCE=0
for a in "$@"; do
  case "$a" in
    --no-config) DO_CONFIG=0 ;;
    --no-hermes) DO_HERMES=0 ;;
    --force) FORCE=1 ;;
    -h|--help) sed -n 2,12p "$0"; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

# id | owner/repo | ref    (ref = branch, tag or commit)
PLUGINS=(
  "herdr-agent-quota|TinocoAI/herdr-agent-quota|hermes-provider"
  "live-sync-panes|TinocoAI/live-sync-panes|tinoco"
  "mirror|nikok6/herdr-mirror|195398c1275f9f3d18ddff70282149005a2bec01"
  "herdr-pane-labels|TinocoAI/herdr-pane-labels|main"
  "herdr-remote-bridge|TinocoAI/herdr-remote-bridge|main"
  "scp-explorer|TinocoAI/scp-explorer|main"
)

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

# --- prerequisites -----------------------------------------------------------
command -v herdr >/dev/null || die "herdr not found (install: https://herdr.dev)"
command -v git >/dev/null || die "git not found"
command -v python3 >/dev/null || die "python3 not found (pane-labels, remote-bridge, scp-explorer)"
command -v cargo >/dev/null || [ -x "$HOME/.cargo/bin/cargo" ] || die "cargo not found (herdr-agent-quota, mirror): https://rustup.rs"
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
command -v bun >/dev/null || command -v node >/dev/null || warn "neither bun nor node on PATH: live-sync-panes needs one of them"
log "herdr $(herdr --version 2>/dev/null | awk '{print $2}') (setup tested with 0.9.5)"

# Corporate TLS interception (e.g. Netskope): point builds at the CA bundle.
for ca in "${SSL_CERT_FILE:-}" "$HOME/.hermes/ssl/custom_bundle.pem"; do
  if [ -n "$ca" ] && [ -f "$ca" ]; then
    export SSL_CERT_FILE="$ca" CARGO_HTTP_CAINFO="$ca" GIT_SSL_CAINFO="$ca" NODE_EXTRA_CA_CERTS="$ca"
    log "using CA bundle $ca"; break
  fi
done

herdr pane list >/dev/null 2>&1 || warn "herdr server not running: plugin startup hooks run on next start"

installed_json() { herdr plugin list --json 2>/dev/null || echo '{"result":{"plugins":[]}}'; }

# prints: "<kind> <owner/repo> <commit>" or nothing when not installed
installed_source() {
  installed_json | python3 -c '
import json, sys
pid = sys.argv[1]
for p in json.load(sys.stdin)["result"]["plugins"]:
    if p["plugin_id"] == pid:
        s = p.get("source") or {}
        print(s.get("kind", "?"), "%s/%s" % (s.get("owner", ""), s.get("repo", "")), s.get("resolved_commit", ""))
' "$1"
}

plugin_root() {
  installed_json | python3 -c '
import json, sys
for p in json.load(sys.stdin)["result"]["plugins"]:
    if p["plugin_id"] == sys.argv[1]:
        print(p["plugin_root"])
' "$1"
}

# --- plugins -----------------------------------------------------------------
for entry in "${PLUGINS[@]}"; do
  IFS='|' read -r id repo ref <<<"$entry"
  cur="$(installed_source "$id")"
  want_commit="$(git ls-remote "https://github.com/$repo.git" "$ref" | awk 'NR==1{print $1}')"
  [ -n "$want_commit" ] || want_commit="$ref"   # ref is already a commit
  if [ -n "$cur" ] && [ "$FORCE" = 0 ]; then
    read -r kind src commit <<<"$cur"
    if [ "$kind" = github ] && [ "$(echo "$src" | tr A-Z a-z)" = "$(echo "$repo" | tr A-Z a-z)" ] && [ "$commit" = "$want_commit" ]; then
      log "$id: up to date ($repo@${commit:0:7})"; continue
    fi
    log "$id: replacing $kind ${src} ${commit:0:7} -> $repo@${want_commit:0:7}"
  fi
  [ -n "$cur" ] && herdr plugin uninstall "$id" >/dev/null 2>&1 || true
  log "$id: installing $repo@$ref"
  herdr plugin install "$repo" --ref "$ref" --yes
  herdr plugin enable "$id" >/dev/null 2>&1 || true
done

# --- Herdr config --------------------------------------------------------------
mkdir -p "$HERDR_CFG/agent-detection"
fetch() { # fetch <repo-relative path> <dest>
  local here; here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
  if [ -n "$here" ] && [ -f "$here/$1" ]; then cp "$here/$1" "$2"; else curl -fsSL "$REPO_RAW/$1" -o "$2"; fi
}
if [ "$DO_CONFIG" = 1 ]; then
  if [ -f "$HERDR_CFG/config.toml" ]; then
    cp "$HERDR_CFG/config.toml" "$HERDR_CFG/config.toml.bak.$(date +%s)"
    log "backed up existing config.toml"
  fi
  fetch herdr/config.toml "$HERDR_CFG/config.toml"
  log "installed config.toml (theme, sidebar quota rows, keybindings)"
fi

QUOTA_ROOT="$(plugin_root herdr-agent-quota)"
HI="$QUOTA_ROOT/hermes-integration"
[ -d "$HI" ] || die "herdr-agent-quota is missing hermes-integration/ (wrong source?)"
cp "$HI/herdr-agent-detection/hermes.toml" "$HERDR_CFG/agent-detection/hermes.toml"
log "installed Hermes agent-detection override"

herdr server reload-config >/dev/null 2>&1 || true
herdr server reload-agent-manifests >/dev/null 2>&1 || true

# --- Hermes side -----------------------------------------------------------------
if [ "$DO_HERMES" = 1 ] && command -v hermes >/dev/null; then
  HP="${HERMES_HOME:-$HOME/.hermes}/plugins"
  mkdir -p "$HP/herdr-agent-state" "$HP/hermes-proctitle" "${HERMES_HOME:-$HOME/.hermes}/vendor"
  cp "$HI/herdr_agent_state.py" "$HP/herdr-agent-state/__init__.py"
  cp "$HI/plugin.yaml" "$HP/herdr-agent-state/plugin.yaml"
  cp "$HI/hermes-proctitle/__init__.py" "$HI/hermes-proctitle/plugin.yaml" "$HP/hermes-proctitle/"
  # durable backups (herdr integration install hermes overwrites herdr-agent-state)
  cp "$HI/herdr_agent_state.py" "${HERMES_HOME:-$HOME/.hermes}/vendor/herdr-agent-state.patched.py"
  cp "$HI/herdr-agent-detection/hermes.toml" "${HERMES_HOME:-$HOME/.hermes}/vendor/herdr-hermes-detection.toml"
  hermes plugins enable herdr-agent-state >/dev/null 2>&1 || warn "could not enable herdr-agent-state"
  hermes plugins enable hermes-proctitle >/dev/null 2>&1 || warn "could not enable hermes-proctitle"
  hermes config set terminal.client_env_passthrough \
    '["HERDR_ENV","HERDR_PANE_ID","HERDR_SOCKET_PATH","HERDR_BIN_PATH","HERDR_SESSION","HERDR_WORKSPACE_ID","HERDR_TAB_ID"]' \
    >/dev/null 2>&1 || warn "could not set terminal.client_env_passthrough"
  log "Hermes integration installed (restart Hermes sessions running in Herdr panes)"
elif [ "$DO_HERMES" = 1 ]; then
  warn "hermes not found: skipped Hermes integration (re-run after installing Hermes)"
fi

herdr plugin action invoke herdr-agent-quota.refresh >/dev/null 2>&1 || true

# --- summary -------------------------------------------------------------------------
log "installed plugins:"
installed_json | python3 -c '
import json, sys
for p in json.load(sys.stdin)["result"]["plugins"]:
    s = p.get("source") or {}
    if s.get("kind") == "github":
        src = "%s/%s@%s" % (s.get("owner"), s.get("repo"), (s.get("resolved_commit") or "")[:7])
    else:
        src = s.get("kind")
    print("   %-22s %-9s %s" % (p["plugin_id"], "enabled" if p.get("enabled") else "DISABLED", src))
'
log "done"
