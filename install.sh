#!/usr/bin/env bash
set -euo pipefail

dotfiles_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
package_manager=""
apt_updated=0
color_reset=""
color_ok=""
color_warn=""
color_error=""
color_skip=""
color_prompt=""

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  color_reset=$'\033[0m'
  color_ok=$'\033[32m'
  color_warn=$'\033[33m'
  color_error=$'\033[31m'
  color_skip=$'\033[36m'
  color_prompt=$'\033[35m'
fi

info() {
  local message="$*"

  case "$message" in
    ok:*) printf '%sok:%s%s\n' "$color_ok" "$color_reset" "${message#ok:}" ;;
    skip:*) printf '%sskip:%s%s\n' "$color_skip" "$color_reset" "${message#skip:}" ;;
    error:*) printf '%serror:%s%s\n' "$color_error" "$color_reset" "${message#error:}" ;;
    warn:*) printf '%swarn:%s%s\n' "$color_warn" "$color_reset" "${message#warn:}" ;;
    *) printf '%s\n' "$message" ;;
  esac
}

warn() {
  printf '%swarn:%s %s\n' "$color_warn" "$color_reset" "$*" >&2
}

error() {
  printf '%serror:%s %s\n' "$color_error" "$color_reset" "$*" >&2
}

have() {
  command -v "$1" >/dev/null 2>&1
}

ask() {
  local prompt="$1"
  local answer

  if [[ ! -t 0 ]]; then
    warn "$prompt skipped because the shell is not interactive"
    return 1
  fi

  printf '%s%s%s [s/N] ' "$color_prompt" "$prompt" "$color_reset"
  read -r answer
  case "$answer" in
    s|S|si|Si|SI|y|Y|yes|Yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

run_as_root() {
  if (( EUID == 0 )); then
    "$@"
  elif have sudo; then
    sudo "$@"
  else
    warn "sudo is not installed; cannot run: $*"
    return 1
  fi
}

detect_package_manager() {
  if have brew; then
    package_manager="brew"
    HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-$(brew --prefix 2>/dev/null || true)}"
    export HOMEBREW_PREFIX
  elif have apt-get; then
    package_manager="apt"
  elif have dnf; then
    package_manager="dnf"
  elif have pacman; then
    package_manager="pacman"
  elif have zypper; then
    package_manager="zypper"
  elif have apk; then
    package_manager="apk"
  else
    package_manager=""
  fi
}

package_for() {
  local tool="$1"

  case "$tool" in
    bat|curl|fzf|git|lsd|zsh) printf '%s\n' "$tool" ;;
    gh)
      case "$package_manager" in
        apk|pacman) printf '%s\n' "github-cli" ;;
        *) printf '%s\n' "gh" ;;
      esac
      ;;
    nvim) printf '%s\n' "neovim" ;;
    *) return 1 ;;
  esac
}

install_packages() {
  case "$package_manager" in
    brew)
      brew install "$@"
      ;;
    apt)
      if (( apt_updated == 0 )); then
        run_as_root apt-get update || return 1
        apt_updated=1
      fi
      run_as_root apt-get install -y "$@"
      ;;
    dnf)
      run_as_root dnf install -y "$@"
      ;;
    pacman)
      run_as_root pacman -S --needed --noconfirm "$@"
      ;;
    zypper)
      run_as_root zypper install -y "$@"
      ;;
    apk)
      run_as_root apk add "$@"
      ;;
    *)
      return 1
      ;;
  esac
}

install_package_tool() {
  local display="$1"
  local check_function="$2"
  local tool="$3"
  local package

  if "$check_function"; then
    info "ok: $display already installed"
    return
  fi

  if [[ -z "$package_manager" ]]; then
    warn "$display is missing and no supported package manager was found"
    return
  fi

  package="$(package_for "$tool")"
  if ask "$display is missing. Install package '$package' with $package_manager?"; then
    if install_packages "$package"; then
      info "ok: installed $display"
    else
      warn "could not install $display"
    fi
  fi
}

fetch_script() {
  local url="$1"
  local target="$2"

  if ! have curl; then
    warn "curl is required to download $url"
    return 1
  fi

  curl -fsSL "$url" -o "$target"
}

make_temp_script() {
  mktemp "${TMPDIR:-/tmp}/dotfiles-install.XXXXXX"
}

run_downloaded_script() {
  local url="$1"
  local runner="$2"
  shift 2

  local tmp
  local status
  tmp="$(make_temp_script)"

  if ! fetch_script "$url" "$tmp"; then
    return 1
  fi

  "$runner" "$tmp" "$@"
  status=$?
  rm -f "$tmp"
  return "$status"
}

clone_repo() {
  local display="$1"
  local repo="$2"
  local target="$3"

  if [[ -e "$target" ]]; then
    info "ok: $display already exists at $target"
    return
  fi

  if ! have git; then
    warn "git is required to install $display"
    return
  fi

  mkdir -p "$(dirname "$target")"
  if ask "$display is missing. Clone it from $repo?"; then
    if git clone --depth=1 "$repo" "$target"; then
      info "ok: installed $display"
    else
      warn "could not install $display"
    fi
  fi
}

check_bat() {
  have bat || have batcat
}

check_curl() {
  have curl
}

check_fzf() {
  have fzf
}

check_git() {
  have git
}

check_gh() {
  have gh
}

check_lsd() {
  have lsd
}

check_nvim() {
  have nvim
}

check_zsh() {
  have zsh
}

check_kitty() {
  have kitty || [[ -d "$HOME/.local/kitty.app" || -d /Applications/kitty.app ]]
}

font_file_exists() {
  local pattern="$1"
  local dir

  for dir in \
    "$HOME/.local/share/fonts" \
    "$HOME/Library/Fonts" \
    /Library/Fonts \
    /usr/local/share/fonts \
    /usr/share/fonts; do
    [[ -d "$dir" ]] || continue
    if find "$dir" -iname "*$pattern*" -print -quit 2>/dev/null | grep -q .; then
      return 0
    fi
  done

  return 1
}

font_family_exists() {
  local family="$1"

  if have fc-list; then
    fc-list : family 2>/dev/null | tr ',' '\n' | grep -Fxiq "$family"
    return
  fi

  if have system_profiler; then
    system_profiler SPFontsDataType 2>/dev/null | grep -Fq "$family"
    return
  fi

  return 1
}

check_shure_tech_mono_font() {
  font_family_exists "ShureTechMono Nerd Font Mono" ||
    font_family_exists "ShureTechMono Nerd Font" ||
    font_file_exists "ShureTechMono" ||
    font_file_exists "ShareTechMono"
}

check_oh_my_zsh() {
  [[ -r "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]]
}

check_powerlevel10k() {
  [[ -r "$HOME/powerlevel10k/powerlevel10k.zsh-theme" ]]
}

check_zsh_syntax_highlighting() {
  [[ -r "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] ||
    [[ -r /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] ||
    [[ -r /usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] ||
    [[ -n "${HOMEBREW_PREFIX:-}" && -r "$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]
}

check_zsh_autosuggestions() {
  [[ -r "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] ||
    [[ -r /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]] ||
    [[ -r /usr/local/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]] ||
    [[ -n "${HOMEBREW_PREFIX:-}" && -r "$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]
}

check_nvm() {
  [[ -s "${NVM_DIR:-$HOME/.nvm}/nvm.sh" ]]
}

install_kitty() {
  if check_kitty; then
    info "ok: Kitty already installed"
    return
  fi

  if ask "Kitty is missing. Install it with the official Kitty installer?"; then
    if ! have curl; then
      warn "curl is required to install Kitty"
      return
    fi

    if curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin launch=n; then
      info "ok: installed Kitty"
    else
      warn "could not install Kitty"
    fi
  fi
}

install_nerd_font_archive() {
  local font_name="$1"
  local font_dir
  local tmp_dir
  local archive

  if ! have curl || ! have tar; then
    warn "curl and tar are required to install $font_name"
    return 1
  fi

  case "$(uname -s)" in
    Darwin) font_dir="$HOME/Library/Fonts" ;;
    Linux) font_dir="$HOME/.local/share/fonts" ;;
    *)
      warn "automatic font installation is only supported on Linux and macOS"
      return 1
      ;;
  esac

  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-font.XXXXXX")"
  archive="$tmp_dir/$font_name.tar.xz"

  mkdir -p "$font_dir"
  if curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/$font_name.tar.xz" -o "$archive" &&
    tar -xf "$archive" -C "$tmp_dir"; then
    find "$tmp_dir" -type f \( -iname "*.ttf" -o -iname "*.otf" \) -exec cp {} "$font_dir/" \;
    have fc-cache && fc-cache -f "$font_dir" >/dev/null 2>&1 || true
    rm -rf "$tmp_dir"
    return 0
  fi

  rm -rf "$tmp_dir"
  error "failed to download or extract $font_name from Nerd Fonts"
  return 1
}

install_shure_tech_mono_font() {
  if check_shure_tech_mono_font; then
    info "ok: ShureTechMono Nerd Font already installed"
    return
  fi

  if [[ "$package_manager" == "brew" ]]; then
    if ask "ShureTechMono Nerd Font is missing. Install cask 'font-shure-tech-mono-nerd-font' with Homebrew?"; then
      if brew install --cask font-shure-tech-mono-nerd-font; then
        info "ok: installed ShureTechMono Nerd Font"
      else
        warn "could not install ShureTechMono Nerd Font"
      fi
    fi
    return
  fi

  if ask "ShureTechMono Nerd Font is missing. Download it from the official Nerd Fonts release?"; then
    if install_nerd_font_archive ShareTechMono; then
      info "ok: installed ShureTechMono Nerd Font"
    else
      warn "could not install ShureTechMono Nerd Font"
    fi
  fi
}

install_oh_my_zsh() {
  if check_oh_my_zsh; then
    info "ok: Oh My Zsh already installed"
    return
  fi

  if ask "Oh My Zsh is missing. Install it with the official installer?"; then
    local tmp
    tmp="$(make_temp_script)"
    if fetch_script https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh "$tmp" &&
      RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh "$tmp"; then
      rm -f "$tmp"
      info "ok: installed Oh My Zsh"
    else
      rm -f "$tmp"
      warn "could not install Oh My Zsh"
    fi
  fi
}

install_powerlevel10k() {
  if check_powerlevel10k; then
    info "ok: Powerlevel10k already installed"
    return
  fi

  clone_repo "Powerlevel10k" \
    https://github.com/romkatv/powerlevel10k.git \
    "$HOME/powerlevel10k"
}

install_zsh_plugins() {
  if check_zsh_syntax_highlighting; then
    info "ok: zsh-syntax-highlighting already installed"
  else
    clone_repo "zsh-syntax-highlighting" \
      https://github.com/zsh-users/zsh-syntax-highlighting.git \
      "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
  fi

  if check_zsh_autosuggestions; then
    info "ok: zsh-autosuggestions already installed"
  else
    clone_repo "zsh-autosuggestions" \
      https://github.com/zsh-users/zsh-autosuggestions.git \
      "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
  fi
}

install_nvm() {
  if check_nvm; then
    info "ok: nvm already installed"
    return
  fi

  if ask "nvm is missing. Install it with the official installer?"; then
    local tmp
    tmp="$(make_temp_script)"
    if fetch_script https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh "$tmp" &&
      PROFILE=/dev/null bash "$tmp"; then
      rm -f "$tmp"
      info "ok: installed nvm"
    else
      rm -f "$tmp"
      warn "could not install nvm"
    fi
  fi
}

install_deno() {
  if have deno; then
    info "ok: Deno already installed"
    return
  fi

  if ask "Deno is missing. Install it with the official shell installer?"; then
    if run_downloaded_script https://deno.land/install.sh sh; then
      info "ok: installed Deno"
    else
      warn "could not install Deno"
    fi
  fi
}

install_pnpm() {
  if have pnpm; then
    info "ok: pnpm already installed"
    return
  fi

  if ask "pnpm is missing. Install it with the official standalone installer?"; then
    local tmp
    tmp="$(make_temp_script)"
    if fetch_script https://get.pnpm.io/install.sh "$tmp" &&
      ENV=/dev/null sh "$tmp"; then
      rm -f "$tmp"
      info "ok: installed pnpm"
    else
      rm -f "$tmp"
      warn "could not install pnpm"
    fi
  fi
}

install_rustup() {
  if have rustup || have cargo; then
    info "ok: Rust/Cargo already installed"
    return
  fi

  if ask "Rust/Cargo is missing. Install it with rustup?"; then
    if run_downloaded_script https://sh.rustup.rs sh -y; then
      info "ok: installed Rust/Cargo"
    else
      warn "could not install Rust/Cargo"
    fi
  fi
}

install_ghcup() {
  if have ghcup || [[ -r "$HOME/.ghcup/env" ]]; then
    info "ok: GHCup already installed"
    return
  fi

  if ask "GHCup is missing. Install it with the official interactive installer?"; then
    if run_downloaded_script https://get-ghcup.haskell.org sh; then
      info "ok: installed GHCup"
    else
      warn "could not install GHCup"
    fi
  fi
}

check_apps() {
  if [[ "${DOTFILES_SKIP_INSTALL_CHECKS:-}" == "1" ]]; then
    info "skip: application checks disabled by DOTFILES_SKIP_INSTALL_CHECKS=1"
    return
  fi

  detect_package_manager
  if [[ -n "$package_manager" ]]; then
    info "package manager: $package_manager"
  else
    warn "no supported package manager found"
  fi

  install_package_tool "curl" check_curl curl
  install_package_tool "Git" check_git git
  install_package_tool "GitHub CLI" check_gh gh
  install_package_tool "Zsh" check_zsh zsh
  install_package_tool "Neovim" check_nvim nvim
  install_package_tool "lsd" check_lsd lsd
  install_package_tool "bat" check_bat bat
  install_package_tool "fzf" check_fzf fzf

  install_kitty
  install_shure_tech_mono_font
  install_oh_my_zsh
  install_powerlevel10k
  install_zsh_plugins
  install_nvm
  install_deno
  install_pnpm
  install_rustup
  install_ghcup
}

link_file() {
  local source="$1"
  local target="$2"

  if [[ -e "$target" && ! -L "$target" ]]; then
    printf 'skip: %s already exists and is not a symlink\n' "$target"
    return
  fi

  ln -sfn "$source" "$target"
  printf 'link: %s -> %s\n' "$target" "$source"
}

prepare_dir() {
  local target="$1"

  if [[ -L "$target" && ! -d "$target" ]]; then
    unlink "$target"
  fi

  mkdir -p "$target"
}

check_apps

prepare_dir "$config_home/kitty"
prepare_dir "$config_home/nvim/lua"

link_file "$dotfiles_dir/kitty.conf" "$config_home/kitty/kitty.conf"
link_file "$dotfiles_dir/.gitconfig" "$HOME/.gitconfig"
link_file "$dotfiles_dir/.zshrc" "$HOME/.zshrc"
link_file "$dotfiles_dir/.p10k.zsh" "$HOME/.p10k.zsh"
link_file "$dotfiles_dir/custom" "$config_home/nvim/lua/custom"
