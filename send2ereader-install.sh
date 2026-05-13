#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts
# Author: antony.ramon
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/daniel-j/send2ereader

# APP is passed in as an env var by the CT script; define fallback just in case
APP="${APP:-Send2eReader}"

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  git \
  curl \
  wget \
  build-essential \
  python3 \
  python3-pip \
  python3-venv \
  pipx
msg_ok "Installed Dependencies"

NODE_VERSION="20" setup_nodejs

msg_info "Installing Kepubify"
KEPUBIFY_VERSION=$(curl -fsSL https://api.github.com/repos/pgaskin/kepubify/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
wget -q "https://github.com/pgaskin/kepubify/releases/download/${KEPUBIFY_VERSION}/kepubify-linux-64bit" -O /usr/local/bin/kepubify
chmod +x /usr/local/bin/kepubify
msg_ok "Installed Kepubify"

msg_info "Installing KindleGen"
wget -q "https://github.com/zzet/fp-docker/raw/f2b41fb0af6bb903afd0e429d5487acc62cb9df8/kindlegen_linux_2.6_i386_v2_9.tar.gz" -O /tmp/kindlegen.tar.gz
mkdir -p /tmp/kindlegen
tar xzf /tmp/kindlegen.tar.gz -C /tmp/kindlegen
cp /tmp/kindlegen/kindlegen /usr/local/bin/kindlegen
chmod +x /usr/local/bin/kindlegen
rm -rf /tmp/kindlegen /tmp/kindlegen.tar.gz
msg_ok "Installed KindleGen"

msg_info "Installing pdfCropMargins"
export PIPX_HOME="/opt/pipx"
export PIPX_BIN_DIR="/usr/local/bin"
$STD pipx install pdfCropMargins
msg_ok "Installed pdfCropMargins"

msg_info "Installing ${APP}"
$STD git clone https://github.com/daniel-j/send2ereader.git /opt/send2ereader
cd /opt/send2ereader
$STD npm install --omit=dev
mkdir -p /opt/send2ereader/uploads
msg_ok "Installed ${APP}"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/send2ereader.service
[Unit]
Description=Send2eReader - Send ebooks to Kobo/Kindle
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/send2ereader
ExecStart=/usr/bin/node /opt/send2ereader/index.js
Restart=on-failure
RestartSec=5
Environment=NODE_ENV=production
Environment=PATH=/usr/local/bin:/usr/bin:/bin

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now send2ereader
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
