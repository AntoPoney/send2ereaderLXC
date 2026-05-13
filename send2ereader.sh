#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts
# Author: antony.ramon
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/daniel-j/send2ereader

APP="Send2eReader"
var_tags="${var_tags:-ebook}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/send2ereader ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Stopping Service"
  systemctl stop send2ereader
  msg_ok "Stopped Service"

  msg_info "Backing up application"
  cd ~
  mkdir -p send2ereader-backup
  cp /opt/send2ereader/package.json send2ereader-backup/
  msg_ok "Backed up application"

  msg_info "Updating ${APP}"
  cd /opt/send2ereader
  $STD git pull
  $STD npm install --omit=dev
  msg_ok "Updated ${APP}"

  msg_info "Starting Service"
  systemctl start send2ereader
  msg_ok "Started Service"

  msg_info "Cleaning up"
  rm -rf ~/send2ereader-backup
  msg_ok "Cleaned up"

  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3001${CL}"
