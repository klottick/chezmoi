#!/bin/bash

PROGRESS_FILE="/tmp/setup_progress"
USE_ZSH=false

if [[ "$1" == "--zsh" ]]; then
  USE_ZSH=true
fi

get_setup_stage() {
  [[ -f "$PROGRESS_FILE" ]] && cat "$PROGRESS_FILE" || echo "0"
}

set_setup_stage() {
  echo "$1" > "$PROGRESS_FILE"
}

switch_to_zsh() {
  echo "Installing Zsh..."
  apt update
  apt install -y zsh
  chsh -s "$(which zsh)"
  echo "Switching to Zsh..."
  exec zsh -l -c "zsh $0 --zsh"
}

SETUP_STAGE=$(get_setup_stage)

if [ "$USE_ZSH" = true ] && [ "$SETUP_STAGE" -eq 0 ]; then
  switch_to_zsh
fi

if [ "$SETUP_STAGE" -eq 0 ]; then
  echo "Removing Google Authenticator config..."
  rm -f /root/.google_authenticator

  echo "Allowing root login..."
  sed -i '1s/.*/PermitRootLogin yes/' /etc/ssh/sshd_config.d/sshd_config.conf
  systemctl restart ssh

  echo "Setting up VPN..."
  cp openvpn.cloudron* /etc/openvpn/client.conf
  systemctl daemon-reload
  systemctl restart openvpn.service

  echo "Installing system packages..."
  apt update
  apt install -y vim python3-dev python3-venv cmake python3-pybind11 \
      libmosquitto-dev fakeroot build-essential unzip git

  echo "Installing UV (pipx replacement)..."
  curl -LsSf https://github.com/astral-sh/uv/releases/latest/download/uv-installer.sh | sh
  export PATH="$HOME/.local/bin:$PATH"

  echo "Installing global Python tools with UV..."
  uv venv
  uv pip install --system cruft poetry pre-commit

  echo "Installing Oh My Zsh..."
  sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

  set_setup_stage 1
  exec "$SHELL" -l -c "bash $0"

elif [ "$SETUP_STAGE" -eq 1 ]; then
  echo "Installing Powerlevel10k..."
  ZSH_CUSTOM=${ZSH_CUSTOM:-~/.oh-my-zsh/custom}
  if [ ! -d "$ZSH_CUSTOM/themes/powerlevel10k" ]; then
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k"
  fi
  sed -i 's/ZSH_THEME=".*"/ZSH_THEME="powerlevel10k\/powerlevel10k"/g' ~/.zshrc

  echo "Adding Zsh plugins..."
  sed -i 's/^plugins=(.*)/plugins=(evalcache poetry git git-extras debian tmux screen history extract colorize web-search docker)/' ~/.zshrc

  echo "Restoring previous Zsh setup (if present)..."
  [ -f "/root/zsh-setup.tar.gz" ] && tar -xzf /root/zsh-setup.tar.gz -C ~

  echo "Installing Node.js via NVM..."
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
  nvm install 20

  echo "Configuring Poetry..."
  poetry config virtualenvs.in-project true

  set_setup_stage 2
  exec "$SHELL" -l -c "bash $0"

elif [ "$SETUP_STAGE" -eq 2 ]; then
  echo "Cloning repositories..."
  mkdir -p /root/repos
  cd /root/repos || exit 1

  declare -A REPOS=(
    ["cpid_500_rfid_driver"]="checkpt/cpid_500_rfid_driver"
    ["cpid-500-rfid-controller"]="checkpt/cpid-500-rfid-controller"
    ["gpio-controller"]="checkpt/gpio-controller"
  )

  for repo_dir in "${!REPOS[@]}"; do
    repo_url="git@github.com:${REPOS[$repo_dir]}.git"
    if [[ ! -d "$repo_dir" ]]; then
      git clone "$repo_url"
      cd "$repo_dir" || continue
      poetry install
      pre-commit install-hooks
      [[ "$repo_dir" == "cpid_500_rfid_driver" ]] && npm install
      cd ..
    else
      echo "Repository $repo_dir already exists, skipping."
    fi
  done

  echo "Setup complete!"
  rm -f "$PROGRESS_FILE"
fi
