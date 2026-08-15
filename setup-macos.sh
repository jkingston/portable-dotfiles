#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/setup-common.sh
. "$script_dir/lib/setup-common.sh"

usage() {
  printf 'Usage: %s [--dry-run]\n' "${0##*/}"
}

dry_run=0
case "${1:-}" in
  "") ;;
  --dry-run) dry_run=1 ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

[[ "$(uname -s)" == Darwin ]] || { printf 'This installer supports macOS only.\n' >&2; exit 1; }

brew_formulae=(bat direnv eza fzf git jq neovim rbw starship zoxide)

if (( dry_run )); then
  ui_title macOS
  if command -v brew >/dev/null 2>&1; then
    for formula in "${brew_formulae[@]}"; do
      if brew list --formula "$formula" >/dev/null 2>&1; then
        ui_action UPDATE "$formula" 'latest from Homebrew; no-op if current'
      else
        ui_action INSTALL "$formula" 'from Homebrew'
      fi
    done
    if brew list --cask ghostty >/dev/null 2>&1; then
      ui_action UPDATE ghostty 'latest Homebrew cask; no-op if current'
    else
      ui_action INSTALL ghostty 'from Homebrew cask'
    fi
  else
    ui_action BLOCKED Homebrew 'required: https://brew.sh'
    for formula in "${brew_formulae[@]}"; do
      ui_action INSTALL "$formula" 'after Homebrew is available'
    done
    ui_action INSTALL ghostty 'after Homebrew is available'
  fi
  if [[ -d "$HOME/.oh-my-zsh/.git" ]]; then
    ui_action UPDATE "$HOME/.oh-my-zsh" 'git pull --ff-only; no-op if current'
  elif [[ -e "$HOME/.oh-my-zsh" ]]; then
    ui_action BLOCKED "$HOME/.oh-my-zsh" 'not a Git checkout; not moved'
  else
    ui_action INSTALL "$HOME/.oh-my-zsh" 'clone Oh My Zsh'
  fi
  describe_command_install_or_update rustup 'official rustup installer'

  describe_shared_links
  describe_link "$repo_dir/config/zsh/zshrc" "$HOME/.zshrc"

  runtime_dir="$(getconf DARWIN_USER_TEMP_DIR)rbw-runtime"
  ui_action ENSURE "$runtime_dir" 'directory, mode 700'
  ui_action WRITE "$HOME/Library/LaunchAgents/rbw-agent.plist" 'only if content changed'
  if [[ -f "$config_home/rbw/config.json" ||
        -f "$HOME/Library/Application Support/rbw/config.json" ]]; then
    ui_action LOAD rbw-agent 'reload only if plist changed'
  else
    ui_action DEFER rbw-agent 'load after rbw is configured'
  fi
  exit 0
fi

command -v brew >/dev/null 2>&1 || { printf 'Install Homebrew first: https://brew.sh\n' >&2; exit 1; }

brew update
brew bundle install --upgrade --file="$repo_dir/Brewfile"

oh_my_zsh="$HOME/.oh-my-zsh"
if [[ -e "$oh_my_zsh" && ! -d "$oh_my_zsh/.git" ]]; then
  printf 'Refusing to replace non-Git Oh My Zsh path: %s\n' "$oh_my_zsh" >&2
  exit 1
elif [[ -d "$oh_my_zsh/.git" ]]; then
  git -C "$oh_my_zsh" pull --ff-only
else
  git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$oh_my_zsh"
fi

ensure_rustup
ensure_rust_toolchain

link_shared_config
link_path "$repo_dir/config/zsh/zshrc" "$HOME/.zshrc" || true

runtime_dir="$(getconf DARWIN_USER_TEMP_DIR)rbw-runtime"
agent_path="$(brew --prefix rbw)/bin/rbw-agent"
launch_dir="$HOME/Library/LaunchAgents"
log_dir="$HOME/Library/Logs"
plist="$launch_dir/rbw-agent.plist"
tmp_plist="$(mktemp)"
changed=0

mkdir -p "$runtime_dir" "$launch_dir" "$log_dir"
chmod 700 "$runtime_dir"

sed \
  -e "s|@AGENT@|$agent_path|g" \
  -e "s|@RUNTIME@|$runtime_dir|g" \
  -e "s|@LOG@|$log_dir/rbw-agent.log|g" \
  "$repo_dir/launchd/rbw-agent.plist.in" >"$tmp_plist"
plutil -lint "$tmp_plist" >/dev/null

if [[ ! -f "$plist" ]] || ! cmp -s "$tmp_plist" "$plist"; then
  install -m 600 "$tmp_plist" "$plist"
  changed=1
fi
rm -f "$tmp_plist"

domain="gui/$(id -u)"
label="rbw-agent"
if [[ -f "$config_home/rbw/config.json" ||
      -f "$HOME/Library/Application Support/rbw/config.json" ]]; then
  if (( changed )) && launchctl print "$domain/$label" >/dev/null 2>&1; then
    launchctl bootout "$domain/$label"
  fi
  if ! launchctl print "$domain/$label" >/dev/null 2>&1; then
    launchctl bootstrap "$domain" "$plist"
  fi
else
  printf 'Configure rbw, then rerun this script to start rbw-agent.\n'
fi

printf 'macOS setup complete.\n'
