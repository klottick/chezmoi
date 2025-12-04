#!/usr/bin/env bash
set -euo pipefail

# ========================
# Config / flags
# ========================
PROGRESS_FILE="/tmp/setup_progress"
APT_FIX_MARKER="/tmp/setup_apt_fixed"
USE_ZSH=false
export DEBIAN_FRONTEND=noninteractive

if [[ "${1:-}" == "--zsh" ]]; then
  USE_ZSH=true
fi

# ========================
# Helpers
# ========================
get_setup_stage() {
  [[ -f "$PROGRESS_FILE" ]] && cat "$PROGRESS_FILE" || echo "0"
}

set_setup_stage() {
  echo "$1" > "$PROGRESS_FILE"
}

log()  { printf '\n[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '\n[WARN %s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

is_shell_zsh() {
  [[ -n "${ZSH_VERSION:-}" ]] || [[ "${SHELL:-}" == */zsh ]]
}

# ========================
# Fix APT sources once (stage 0 only)
# Apply to the first 2 lines only, using your original method.
# ========================
fix_apt_sources_once() {
  if [[ -f "$APT_FIX_MARKER" ]]; then
    log "APT sources already fixed earlier; skipping."
    return 0
  fi

  log "Fixing APT sources"

  # Restore from backup exactly as you had it
  if [[ -d /etc/apt/sources.list.d.backup ]]; then
    cp /etc/apt/sources.list.d.backup/* /etc/apt/sources.list.d/ 2>/dev/null || true
  fi

  FILE="/etc/apt/sources.list.d/cpid500-arm64-jammy.list"
  if [[ -f "$FILE" ]]; then
    # Limit substitution to the first 2 lines only
    sed -E -i '1,2{s|https://pool\.checkpoint-service\.com/apt/([^/]+)/|https://pool.checkpoint-service.com:8443/apt/\1-dev/|g}' "$FILE"
    log "Rewrote checkpoint pool in: $FILE (lines 1–2 only)"
  else
    warn "Expected APT list not found: $FILE (skipping rewrite)"
  fi

  apt-get update -y
  touch "$APT_FIX_MARKER"
}

# ========================
# Optional: switch to Zsh
# ========================
switch_to_zsh() {
  log "Installing Zsh and switching shell…"
  apt-get install -y zsh
  chsh -s "$(command -v zsh)" || warn "chsh failed; continuing"

  # Re-exec into zsh, keep the --zsh flag so stage logic continues
  log "Re-exec into zsh login shell…"
  exec zsh -lc "zsh $0 --zsh"
}

allow_wan_ssh() {
  ZONE_FILE="/etc/firewalld/zones/public.xml"
  
  # Sanity check
  if [[ ! -f "$ZONE_FILE" ]]; then
      log "Error: $ZONE_FILE does not exist." >&2
      return 1
  fi
  
  # If already present, nothing to do
  if grep -q '<service name="ssh"' "$ZONE_FILE"; then
      log "SSH service already present in public zone."
      return 0
  fi
  
  # Insert before the closing </zone> tag
  # Keeps indentation sane
  sed -i '/<\/zone>/i \  <service name="ssh"/>' "$ZONE_FILE"
  
  log "Added <service name=\"ssh\"/> to $ZONE_FILE"
  
  # Reload firewalld so it sees the change
  if systemctl is-active --quiet firewalld; then
      firewall-cmd --reload
      echo "firewalld reloaded."
  fi
}

# ========================
# Run
# ========================
SETUP_STAGE="$(get_setup_stage)"

# Run the APT source fix ONLY at the beginning (stage 0).
if [[ "$SETUP_STAGE" -eq 0 ]]; then
  fix_apt_sources_once
fi

# If user asked to run under zsh and we're at stage 0, hop shells only if not already in zsh.
if [[ "$USE_ZSH" == true && "$SETUP_STAGE" -eq 0 && "$(is_shell_zsh; echo $?)" -ne 0 ]]; then
  switch_to_zsh
fi

if [[ "$SETUP_STAGE" -eq 0 ]]; then
  log "Removing Google Authenticator config…"
  rm -f /root/.google_authenticator

  log "Setting up wan ssh"
  allow_wan_ssh

  log "Allowing root SSH login + enabling global PubkeyAuthentication…"
  mkdir -p /etc/ssh/sshd_config.d
  CONF="/etc/ssh/sshd_config.d/sshd_config.conf"


  # Ensure file exists
  [[ -f "$CONF" ]] || : > "$CONF"

  # 1) Ensure PermitRootLogin yes (replace if present, otherwise append)
  if grep -q '^PermitRootLogin' "$CONF"; then
    sed -i 's/^PermitRootLogin.*/PermitRootLogin yes/' "$CONF"
  else
    # Place near top to be in the global section
    sed -i '1i PermitRootLogin yes' "$CONF"
  fi

  # 2) Ensure **global** PubkeyAuthentication yes (before any Match blocks)
  #    - Replace any existing global PubkeyAuthentication line
  #    - If none exists globally, insert one before the first Match (or append if no Match)
  tmpfile="$(mktemp)"
  awk '
    BEGIN{in_match=0; done=0}
    {
      if ($0 ~ /^Match[ \t]/) { in_match=1 }
      if (!in_match && $0 ~ /^PubkeyAuthentication[ \t]/) {
        if (!done) { print "PubkeyAuthentication yes"; done=1 }
        # skip original global PubkeyAuthentication line
        next
      }
      print $0
    }
    END{
      if (!done) {
        # If no global PubkeyAuthentication was present, add one to the top
        # Caller inserted PermitRootLogin at top already; placing just after is fine.
        # We signal by printing a special marker; will be repositioned below if needed.
      }
    }
  ' "$CONF" > "$tmpfile"

  # If we still don’t have a global PubkeyAuthentication line, inject it before the first Match
  if ! grep -qE '^[[:space:]]*PubkeyAuthentication[[:space:]]+yes[[:space:]]*$' "$tmpfile"; then
    if grep -q '^Match[[:space:]]' "$tmpfile"; then
      # Insert before first Match block
      awk '
        BEGIN{inserted=0}
        {
          if (!inserted && $0 ~ /^Match[ \t]/) {
            print "PubkeyAuthentication yes"
            inserted=1
          }
          print $0
        }
        END{
          if (!inserted) print "PubkeyAuthentication yes"
        }
      ' "$tmpfile" > "${tmpfile}.2"
      mv "${tmpfile}.2" "$tmpfile"
    else
      # No Match blocks; append
      printf "%s\n" "PubkeyAuthentication yes" >> "$tmpfile"
    fi
  fi

  # Persist changes
  cat "$tmpfile" > "$CONF"
  rm -f "$tmpfile"

  if command -v ckp-allow-root-ssh >/dev/null 2>&1; then
    ckp-allow-root-ssh || warn "ckp-allow-root-ssh failed; continuing"
  fi
  systemctl restart ssh || warn "could not restart ssh; continuing"

  log "Setting up VPN…"
  if compgen -G "openvpn.cloudron*" > /dev/null; then
    install -d /etc/openvpn
    cp openvpn.cloudron* /etc/openvpn/client.conf
    systemctl daemon-reload || true
    systemctl restart openvpn.service || warn "openvpn.service restart failed"
  else
    warn "No openvpn.cloudron* file found; skipping VPN copy"
  fi

  log "Installing system packages…"
  apt-get install -y \
    vim python3-dev python3-venv cmake python3-pybind11 \
    libmosquitto-dev fakeroot build-essential unzip git gcc curl ca-certificates \
    gh
  apt-get install -y ckp-python3.13 ckp-python3.13-extras ckp-python3.13-headers
  log "Installing uv (Python toolchain)…"
  curl -LsSf https://github.com/astral-sh/uv/releases/latest/download/uv-installer.sh | sh
  export PATH="$HOME/.local/bin:$PATH"

  log "Installing global Python tools via uv tools…"
  uv tool install pre-commit
  uv tool install cruft

  log "Installing Oh My Zsh (non-interactive)…"
  export RUNZSH=no
  export CHSH=no
  sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" || warn "Oh My Zsh install returned nonzero"

  set_setup_stage 1
  exec "$SHELL" -lc "bash $0"

elif [[ "$SETUP_STAGE" -eq 1 ]]; then
  log "Installing Powerlevel10k…"
  OHMY="${OHMY:-$HOME/.oh-my-zsh}"
  ZSH_CUSTOM="${ZSH_CUSTOM:-$OHMY/custom}"
  THEME_DIR="$ZSH_CUSTOM/themes/powerlevel10k"

  # Ensure parent directories exist (some installers defer this)
  mkdir -p "$ZSH_CUSTOM/themes"

  if [[ ! -d "$THEME_DIR/.git" ]]; then
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$THEME_DIR"
  else
    git -C "$THEME_DIR" pull --ff-only || true
  fi

  # --- Node 24 via NVM; make it default with `nvm alias default` ---
  log "Installing Node Version Manager (nvm)…"
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  mkdir -p "$NVM_DIR"
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
  # shellcheck disable=SC1090
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

  log "Installing Node.js 24 and setting it as the default…"
  nvm install 24
  nvm alias default 24
  nvm use default
  corepack enable || true
  log "Node version: $(node -v)  | npm: $(npm -v)"

  set_setup_stage 2
  exec "$SHELL" -lc "bash $0"

elif [[ "$SETUP_STAGE" -eq 2 ]]; then
  log "Cloning repositories…"
  mkdir -p /root/repos
  cd /root/repos

  declare -A REPOS=(
    ["cpid-500-ui"]="checkpt/cpid-500-ui"
    ["cpid-500-rfid-controller"]="checkpt/cpid-500-rfid-controller"
    ["gpio-controller"]="checkpt/gpio-controller"
  )

  for repo_dir in "${!REPOS[@]}"; do
    repo_url="git@github.com:${REPOS[$repo_dir]}.git"
    if [[ ! -d "$repo_dir/.git" ]]; then
      log "Cloning $repo_url → $repo_dir"
      git clone --filter=blob:none "$repo_url" "$repo_dir"
      pushd "$repo_dir" >/dev/null

      # Python deps (uv will pick up pyproject if present)
      if [[ -f pyproject.toml ]]; then
        uv sync || warn "uv sync failed in $repo_dir"
      fi

      # Pre-commit hooks (only if config exists)
      if [[ -f .pre-commit-config.yaml ]]; then
        pre-commit install --install-hooks || warn "pre-commit hook install failed in $repo_dir"
      fi

      # Node deps only for the driver repo (per your original)
      if [[ "$repo_dir" == "cpid-500-ui" && -f package.json ]]; then
        npm install || warn "npm install failed in $repo_dir"
      fi

      popd >/dev/null
    else
      log "Repository $repo_dir already exists; pulling latest…"
      (cd "$repo_dir" && git pull --ff-only) || warn "git pull failed in $repo_dir"
    fi
  done

  log "Setup complete!"
  rm -f "$PROGRESS_FILE"
fi
