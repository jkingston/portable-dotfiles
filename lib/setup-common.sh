#!/usr/bin/env bash

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
rust_toolchain="stable"

ui_init() {
  ui_reset='' ui_bold='' ui_dim=''
  ui_green='' ui_blue='' ui_cyan='' ui_magenta='' ui_yellow='' ui_red=''
  if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    ui_reset=$'\033[0m' ui_bold=$'\033[1m' ui_dim=$'\033[2m'
    ui_green=$'\033[32m' ui_blue=$'\033[34m' ui_cyan=$'\033[36m'
    ui_magenta=$'\033[35m' ui_yellow=$'\033[33m' ui_red=$'\033[31m'
  fi
}

ui_title() {
  local platform="$1"
  printf '%s%s%s\n' "$ui_bold" "$platform setup plan" "$ui_reset"
  printf '%sNo changes will be made.%s\n' "$ui_dim" "$ui_reset"
}

ui_section() {
  printf '\n%s%s%s\n' "$ui_bold" "$1" "$ui_reset"
}

ui_action() {
  local status="$1" subject="$2" detail="$3" symbol color
  case "$status" in
    INSTALL) symbol='+'; color="$ui_green" ;;
    UPDATE)  symbol='↑'; color="$ui_blue" ;;
    SYMLINK) symbol='→'; color="$ui_magenta" ;;
    MOVE)    symbol='↪'; color="$ui_yellow" ;;
    KEEP)    symbol='✓'; color="$ui_green" ;;
    BLOCKED) symbol='!'; color="$ui_yellow" ;;
    ENABLE|START|LOAD) symbol='●'; color="$ui_cyan" ;;
    DEFER)   symbol='○'; color="$ui_yellow" ;;
    ENSURE|WRITE) symbol='◆'; color="$ui_magenta" ;;
    NONE)    symbol='–'; color="$ui_dim" ;;
    *)       symbol='·'; color='' ;;
  esac
  printf '  %s%s  %-8s%s %-22s %s\n' \
    "$color" "$symbol" "$status" "$ui_reset" "$subject" "$detail"
}

ui_init

describe_link() {
  local source="$1" target="$2" backup
  backup="$target.pre-dotfiles"

  if [[ -L "$target" ]]; then
    if [[ "$target" -ef "$source" ]]; then
      ui_action KEEP "$target" "→ $source"
    elif [[ -e "$backup" || -L "$backup" ]]; then
      ui_action BLOCKED "$target" "backup already exists: $backup"
    else
      ui_action MOVE "$target" "→ $backup"
      ui_action SYMLINK "$target" "→ $source"
    fi
  elif [[ -e "$target" ]]; then
    if [[ -e "$backup" || -L "$backup" ]]; then
      ui_action BLOCKED "$target" "backup already exists: $backup"
    else
      ui_action MOVE "$target" "→ $backup"
      ui_action SYMLINK "$target" "→ $source"
    fi
  else
    ui_action SYMLINK "$target" "→ $source"
  fi
}

describe_shared_links() {
  describe_link "$repo_dir/config/nvim" "$config_home/nvim"
  describe_link "$repo_dir/config/ghostty" "$config_home/ghostty"
  describe_link "$repo_dir/config/starship" "$config_home/starship"
  describe_link "$repo_dir/bin/ssh-hosts" "$HOME/.local/bin/ssh-hosts"
  describe_link "$repo_dir/bin/rbw-add-note" "$HOME/.local/bin/rbw-add-note"
  describe_link "$repo_dir/config/ssh/config" "$HOME/.ssh/config"
}

describe_command_install_or_update() {
  local command="$1" provider="$2"
  if command -v "$command" >/dev/null 2>&1; then
    ui_action UPDATE "$command" "latest via $provider; no-op if current"
  else
    ui_action INSTALL "$command" "via $provider"
  fi
}

ensure_rustup() {
  if [[ ! -x "$HOME/.cargo/bin/rustup" ]]; then
    local installer
    installer="$(mktemp)"
    curl --proto '=https' --tlsv1.2 --fail --silent --show-error \
      https://sh.rustup.rs --output "$installer"
    sh "$installer" -y --no-modify-path --profile minimal --default-toolchain none
    rm -f "$installer"
  fi
  export PATH="$HOME/.cargo/bin:$PATH"
}

ensure_rust_toolchain() {
  rustup update "$rust_toolchain"
  rustup component add --toolchain "$rust_toolchain" rust-analyzer rustfmt clippy
  rustup default "$rust_toolchain"
}

link_path() {
  local source="$1" target="$2" backup
  backup="$target.pre-dotfiles"

  if [[ ! -e "$source" ]]; then
    printf 'Missing source: %s\n' "$source" >&2
    return 1
  fi

  mkdir -p "$(dirname -- "$target")"

  if [[ -L "$target" ]]; then
    if [[ "$target" -ef "$source" ]]; then
      printf 'Already linked: %s\n' "$target"
      return
    fi
  fi

  if [[ -e "$target" || -L "$target" ]]; then
    if [[ -e "$backup" || -L "$backup" ]]; then
      printf 'Refusing to move %s: backup already exists: %s\n' \
        "$target" "$backup" >&2
      return 1
    fi
    mv -- "$target" "$backup"
    printf 'Moved %s -> %s\n' "$target" "$backup"
  fi

  if ! ln -s "$source" "$target"; then
    if [[ -e "$backup" || -L "$backup" ]]; then
      mv -- "$backup" "$target"
      printf 'Restored %s after symlink failure.\n' "$target" >&2
    fi
    return 1
  fi
  printf 'Linked %s -> %s\n' "$target" "$source"
}

link_shared_config() {
  # A protected existing config should not prevent unrelated links from being
  # installed. link_path still reports every refusal prominently.
  link_path "$repo_dir/config/nvim" "$config_home/nvim" || true
  link_path "$repo_dir/config/ghostty" "$config_home/ghostty" || true
  link_path "$repo_dir/config/starship" "$config_home/starship" || true
  link_path "$repo_dir/bin/ssh-hosts" "$HOME/.local/bin/ssh-hosts" || true
  link_path "$repo_dir/bin/rbw-add-note" "$HOME/.local/bin/rbw-add-note" || true
  link_path "$repo_dir/config/ssh/config" "$HOME/.ssh/config" || true
}
