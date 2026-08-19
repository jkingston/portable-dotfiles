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

[[ -r /etc/os-release ]] || { printf 'Cannot identify this OS.\n' >&2; exit 1; }
# shellcheck disable=SC1091
. /etc/os-release
[[ "${ID:-}" == fedora ]] || { printf 'This installer supports Fedora only.\n' >&2; exit 1; }

fedora_packages=(
  bat curl direnv dnf-plugins-core eza flatpak fzf gcc gh git jq neovim
  openssh-clients pinentry python3 util-linux wl-clipboard zoxide
)
tailscale_repo_url='https://pkgs.tailscale.com/stable/fedora/tailscale.repo'
tailscale_qs_uuid='tailscale-gnome-qs@tailscale-qs.github.io'
tailscale_qs_url='https://extensions.gnome.org/extension/9193/tailscale-qs/'
kagi_addon_url='https://addons.mozilla.org/firefox/addon/kagi-search-for-firefox/'
bitwarden_addon_url='https://addons.mozilla.org/firefox/addon/bitwarden-password-manager/'
case "$(uname -m)" in
  x86_64) chatgpt_rpm_url='https://persistent.oaistatic.com/codex-app-prod/linux/rpm/latest/chatgpt.x86_64.rpm' ;;
  aarch64|arm64) chatgpt_rpm_url='https://persistent.oaistatic.com/codex-app-prod/linux/rpm/latest/chatgpt.aarch64.rpm' ;;
  *) chatgpt_rpm_url='' ;;
esac

zen_has_extension() {
  local addon_id="$1" addon_name="$2" extensions_file
  while IFS= read -r extensions_file; do
    if jq -e --arg id "$addon_id" --arg name "$addon_name" \
      '.addons[]? | select(.id == $id or .defaultLocale.name == $name)' \
      "$extensions_file" >/dev/null 2>&1; then
      return 0
    fi
  done < <(find "$HOME/.var/app/app.zen_browser.zen" -maxdepth 4 \
    -name extensions.json -type f 2>/dev/null)
  return 1
}

if (( dry_run )); then
  ui_title Fedora
  for package in "${fedora_packages[@]}"; do
    if rpm -q "$package" >/dev/null 2>&1; then
      ui_action UPDATE "$package" 'latest from Fedora; no-op if current'
    else
      ui_action INSTALL "$package" 'from Fedora repositories'
    fi
  done
  if flatpak info app.zen_browser.zen >/dev/null 2>&1; then
    ui_action UPDATE 'Zen Browser' 'latest stable release from Flathub; no-op if current'
  else
    ui_action INSTALL 'Zen Browser' 'stable release from Flathub'
  fi
  if rpm -q chatgpt >/dev/null 2>&1; then
    ui_action KEEP ChatGPT 'installed; updates are managed by the app'
  elif [[ -n "$chatgpt_rpm_url" ]]; then
    ui_action INSTALL ChatGPT 'official OpenAI RPM for Fedora'
  else
    ui_action BLOCKED ChatGPT "unsupported architecture: $(uname -m)"
  fi
  ui_action ENSURE 'Tailscale repository' 'official stable Fedora repository'
  if rpm -q tailscale >/dev/null 2>&1; then
    ui_action UPDATE tailscale 'latest stable release; no-op if current'
  else
    ui_action INSTALL tailscale 'from the official stable repository'
  fi
  if /usr/bin/systemctl is-enabled tailscaled.service >/dev/null 2>&1; then
    ui_action KEEP tailscaled.service 'enabled system service'
  else
    ui_action ENABLE tailscaled.service 'enable and start system service'
  fi
  describe_command_install_or_update ghostty 'scottames/ghostty COPR'
  describe_command_install_or_update rustup 'official rustup installer'
  describe_command_install_or_update starship 'Cargo/crates.io'
  describe_command_install_or_update rbw 'Cargo/crates.io'

  describe_shared_links
  describe_link "$repo_dir/config/bash/bashrc" "$HOME/.bashrc.d/50-dotfiles.sh"
  describe_link "$repo_dir/systemd/user/rbw-agent.service" "$config_home/systemd/user/rbw-agent.service"

  ui_action ENABLE rbw-agent.service 'enable for this user'
  if [[ -f "$config_home/rbw/config.json" ]]; then
    ui_action START rbw-agent.service 'rbw configuration found'
  else
    ui_action DEFER rbw-agent.service 'start after rbw is configured'
  fi
  ui_action ENSURE 'Tailscale operator' 'allow this user to control Tailscale'
  if gnome-extensions info "$tailscale_qs_uuid" >/dev/null 2>&1; then
    if gnome-extensions list --enabled | grep -Fxq "$tailscale_qs_uuid"; then
      ui_action KEEP 'Tailscale QS' 'installed and enabled'
    else
      ui_action ENABLE 'Tailscale QS' 'installed GNOME Shell extension'
    fi
  else
    ui_action DEFER 'Tailscale QS' 'install from GNOME Extensions'
  fi
  if zen_has_extension 'search@kagi.com' 'Kagi Search for Firefox'; then
    ui_action KEEP 'Kagi extension' 'already installed in Zen'
  else
    ui_action DEFER 'Kagi extension' 'open official add-on page in Zen and approve'
  fi
  if zen_has_extension '{446900e4-71c2-419f-a6a7-df9c091e268b}' 'Bitwarden Password Manager'; then
    ui_action KEEP 'Bitwarden extension' 'already installed in Zen'
  else
    ui_action DEFER 'Bitwarden extension' 'open official add-on page in Zen and approve'
  fi
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    ui_action KEEP 'GitHub authentication' 'GitHub CLI is authenticated'
  else
    ui_action DEFER 'GitHub authentication' 'run gh auth login after setup'
  fi
  exit 0
fi

sudo dnf install -y "${fedora_packages[@]}"

if flatpak info --system app.zen_browser.zen >/dev/null 2>&1; then
  sudo flatpak update --system -y app.zen_browser.zen
elif flatpak info --user app.zen_browser.zen >/dev/null 2>&1; then
  flatpak update --user -y app.zen_browser.zen
else
  sudo flatpak remote-add --system --if-not-exists \
    flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  sudo flatpak install --system -y flathub app.zen_browser.zen
fi

if ! rpm -q chatgpt >/dev/null 2>&1 && [[ -n "$chatgpt_rpm_url" ]]; then
  chatgpt_rpm_tmp="$(mktemp --suffix=.rpm)"
  trap 'rm -f "$chatgpt_rpm_tmp"' EXIT
  curl -fsSL "$chatgpt_rpm_url" -o "$chatgpt_rpm_tmp"
  sudo dnf install -y "$chatgpt_rpm_tmp"
  rm -f "$chatgpt_rpm_tmp"
  trap - EXIT
elif ! rpm -q chatgpt >/dev/null 2>&1; then
  printf 'ChatGPT does not provide an RPM for architecture %s.\n' "$(uname -m)" >&2
  exit 1
fi

tailscale_repo_tmp="$(mktemp)"
trap 'rm -f "$tailscale_repo_tmp"' EXIT
curl -fsSL "$tailscale_repo_url" -o "$tailscale_repo_tmp"
if ! sudo cmp -s "$tailscale_repo_tmp" /etc/yum.repos.d/tailscale.repo; then
  sudo install -m 0644 "$tailscale_repo_tmp" /etc/yum.repos.d/tailscale.repo
fi
sudo dnf install --refresh -y tailscale
sudo /usr/bin/systemctl enable --now tailscaled.service
rm -f "$tailscale_repo_tmp"
trap - EXIT

if ! command -v ghostty >/dev/null 2>&1; then
  sudo dnf copr enable -y scottames/ghostty
fi
sudo dnf install -y ghostty

ensure_rustup
ensure_rust_toolchain

cargo install --locked starship
cargo install --locked rbw

link_shared_config
link_path "$repo_dir/config/bash/bashrc" "$HOME/.bashrc.d/50-dotfiles.sh" || true
link_path "$repo_dir/systemd/user/rbw-agent.service" "$config_home/systemd/user/rbw-agent.service"

/usr/bin/systemctl --user daemon-reload
/usr/bin/systemctl --user enable rbw-agent.service
if [[ -f "$config_home/rbw/config.json" ]]; then
  /usr/bin/systemctl --user start rbw-agent.service
else
  printf 'Configure rbw, then rerun this script to start rbw-agent.\n'
fi

printf '\nFedora setup complete.\n'

if tailscale status --json 2>/dev/null |
  jq -e '.BackendState == "Running"' >/dev/null; then
  sudo tailscale set --operator="$USER"
else
  printf '\nNext step — connect this machine to your tailnet:\n'
  printf '  sudo tailscale up\n'
  printf '  sudo tailscale set --operator=%q\n' "$USER"
fi

if gnome-extensions info "$tailscale_qs_uuid" >/dev/null 2>&1; then
  if ! gnome-extensions list --enabled | grep -Fxq "$tailscale_qs_uuid"; then
    printf '\nNext step — enable Tailscale QS:\n'
    printf '  gnome-extensions enable %q\n' "$tailscale_qs_uuid"
  fi
else
  printf '\nNext step — install Tailscale QS, then approve the prompt:\n'
  printf '  xdg-open %q\n' "$tailscale_qs_url"
fi

missing_zen_extensions=()
zen_has_extension 'search@kagi.com' 'Kagi Search for Firefox' || missing_zen_extensions+=("$kagi_addon_url")
zen_has_extension '{446900e4-71c2-419f-a6a7-df9c091e268b}' 'Bitwarden Password Manager' ||
  missing_zen_extensions+=("$bitwarden_addon_url")
if (( ${#missing_zen_extensions[@]} )); then
  printf '\nZen extensions — open the missing add-on page(s) and approve:\n'
  printf '  flatpak run app.zen_browser.zen'
  printf ' %q' "${missing_zen_extensions[@]}"
  printf '\n'
fi

if ! gh auth status >/dev/null 2>&1; then
  printf '\nGitHub CLI — authenticate before creating or pushing repositories:\n'
  printf '  gh auth login\n'
fi
