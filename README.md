# Portable dotfiles

Application-focused configuration for Bash on Fedora, Oh My Zsh on macOS,
Neovim, Ghostty, Starship, rbw's SSH agent, and Bitwarden-backed SSH host
aliases. It deliberately avoids
desktop-environment, power-management, driver, and general operating-system
preferences.

## Install

Clone this repository, then run the matching idempotent installer:

```bash
./setup-fedora.sh
./setup-macos.sh
```

Preview either installer without changing the machine:

```bash
./setup-fedora.sh --dry-run
./setup-macos.sh --dry-run
```

Dry-run output distinguishes missing packages from installed packages that
would be checked for updates, lists every planned or existing symlink, reports
generated files and service actions, and identifies conflicts. Before creating
a managed symlink, setup preserves an existing target as `TARGET.pre-dotfiles`.
It never overwrites an existing `.pre-dotfiles` backup.

The scripts install dependencies and create symlinks. They refuse to replace
existing files or symlinks that point elsewhere. Move existing configurations
into this repository before running an installer.

Repository-managed configuration and helper files are symlinked, so `git pull`
updates the active Neovim, Ghostty, SSH, ssh-hosts, and Fedora systemd-agent
configuration immediately. Bitwarden-derived files such as
`~/.ssh/config.d/rbw-*.conf` and `~/.ssh/rbw/*.pub` are generated regular files.

Fedora's existing `.bashrc` is preserved; it loads the managed fragment through
`~/.bashrc.d/50-dotfiles.sh`. macOS keeps its default zsh, installs or updates
Oh My Zsh under `~/.oh-my-zsh`, and links the repository's config as `~/.zshrc`.
The shell toolset includes bat, direnv, eza, fzf, Starship, and zoxide.
Fedora also installs GitHub CLI and prompts for `gh auth login` after setup when
it is not already authenticated.

The macOS installer requires Homebrew. Both installers use the official rustup
installer and update the stable default-profile toolchain whenever setup runs.
Existing rustup installations under `~/.cargo/bin` are reused. The Fedora
installer uses the community Ghostty COPR and installs current rbw and Starship
releases through rustup's Cargo. It also configures Tailscale's official stable
Fedora repository, installs or upgrades Tailscale, and enables `tailscaled`.
Joining a tailnet remains an explicit step: run `sudo tailscale up` after setup.
On GNOME, setup also configures the current user as the Tailscale operator when
connected and provides an installation or enable command for the community-
maintained Tailscale QS extension.
It installs or updates Zen Browser from Flathub as well. The setup completion
message links to the official Kagi Search and Bitwarden Firefox add-ons, which
Zen supports; approve their requested permissions interactively in Zen.
On supported Fedora systems, it installs the official ChatGPT desktop preview
using OpenAI's architecture-specific latest RPM when absent. Existing installs
are left alone so ChatGPT can manage its own updates.

Rustup installs its proxies under `~/.cargo/bin`. Add that directory
to your interactive shell's `PATH` if it is not already present:

```bash
export PATH="$HOME/.cargo/bin:$PATH"
```

The stable channel is also recorded in `rust-toolchain.toml`. Re-running setup
updates Rust, Cargo-installed tools, Fedora packages named by the script, and
Homebrew packages named by the Brewfile to their latest available releases.

## Configure rbw

For an account on bitwarden.com:

```bash
rbw register
rbw config set email you@example.com
rbw login
rbw unlock
rbw sync
```

Rerun the platform installer after creating rbw's config so it starts the user
agent. Private SSH keys must be stored as Bitwarden SSH Key items.

## Configure SSH hosts

Create one Bitwarden Secure Note per host with the helper:

```bash
ssh-hosts add server server.example.com user ssh/keys/server
```

This creates `ssh/hosts/server`; its note contains only the host metadata as
JSON. The optional final argument sets a non-default port. Private SSH keys
remain in separate Bitwarden SSH Key items. Synchronize and test with:

`rbw-add-note` is a narrow companion used only to create Secure Notes. It asks
the unlocked rbw agent to encrypt the item and submits it with rbw's cached
session; access tokens and encryption keys are never passed as command-line
arguments.

```bash
rbw sync
ssh-hosts sync
ssh-hosts list
ssh-hosts test server
```

The generator writes one `~/.ssh/config.d/rbw-<alias>.conf` fragment per host
and public-key selector files under `~/.ssh/rbw`. An empty set of host notes is
valid and produces an empty generated configuration. Private keys remain in
Bitwarden and are exposed only by rbw-agent.

## Notes

- The Neovim configuration requires Neovim 0.12 or newer.
- Ghostty reads `~/.config/ghostty/config.ghostty` on Linux and macOS.
- A macOS config under `~/Library/Application Support/com.mitchellh.ghostty`
  has higher priority and may override this repository's Ghostty settings.
