#!/usr/bin/env bash
# Copyright (c) 2021-2026 community-scripts
# Author: antony.ramon
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/daniel-j/send2ereader

# -----------------------------------------------------------------------
# Self-contained LXC creator for Send2eReader
# Run this script on your Proxmox VE host.
# -----------------------------------------------------------------------

APP="Send2eReader"
NSAPP="send2ereader"
INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/AntoPoney/send2ereaderLXC/refs/heads/main/send2ereader-install.sh"
FUNCTIONS_URL="https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/install.func"

# --- Default container settings ---
var_os="debian"
var_version="12"
var_cpu="1"
var_ram="512"
var_disk="4"
var_unprivileged="1"
var_hostname="${NSAPP}"
var_tags="ebook"
var_mac=""
var_root_password=""
var_ssh="0"

# -----------------------------------------------------------------------
# Color helpers
# -----------------------------------------------------------------------
YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
GN=$(echo "\033[1;92m")
CL=$(echo "\033[m")
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"
INFO="[i]"
TAB="  "

msg_info()  { echo -e "${TAB}${YW}[...] $1${CL}"; }
msg_ok()    { echo -e "${TAB}${CM} ${GN}$1${CL}"; }
msg_error() { echo -e "${TAB}${CROSS} ${RD}$1${CL}"; }

header_info() {
  clear
  cat <<"EOF"
   _____                 _  ____      ____                _
  / ____|               | ||___ \    |  _ \              | |
 | (___   ___ _ __   __| |  __) |___| |_) | ___  __ _  _| | ___ _ __
  \___ \ / _ \ '_ \ / _` | |__ < __|  _ < / _ \/ _` |/ _` |/ _ \ '__|
  ____) |  __/ | | | (_| | ___) \__ \ |_) |  __/ (_| | (_| |  __/ |
 |_____/ \___|_| |_|\__,_||____/|___/____/ \___|\__,_|\__,_|\___|_|

EOF
  echo -e "${BL}  Community-style LXC Script${CL} — ${GN}${APP}${CL}"
  echo
}

# -----------------------------------------------------------------------
# Pre-flight checks
# -----------------------------------------------------------------------
if ! command -v pveversion &>/dev/null; then
  msg_error "This script must be run on a Proxmox VE host."
  exit 1
fi

if [[ "$(id -u)" -ne 0 ]]; then
  msg_error "This script must be run as root."
  exit 1
fi

header_info

CTID=$(pvesh get /cluster/nextid)

# -----------------------------------------------------------------------
# Interactive configuration menu
# -----------------------------------------------------------------------
function advanced_settings() {
  var_cpu=$(whiptail --inputbox "Number of CPU cores" 8 58 "$var_cpu" --title "CPU Cores" 3>&1 1>&2 2>&3) || var_cpu=1
  var_ram=$(whiptail --inputbox "Amount of RAM (MB)" 8 58 "$var_ram" --title "RAM (MB)" 3>&1 1>&2 2>&3) || var_ram=512
  var_disk=$(whiptail --inputbox "Disk size (GB)" 8 58 "$var_disk" --title "Disk Size (GB)" 3>&1 1>&2 2>&3) || var_disk=4
  var_hostname=$(whiptail --inputbox "Container hostname" 8 58 "$var_hostname" --title "Hostname" 3>&1 1>&2 2>&3) || var_hostname=$NSAPP
  
  var_unprivileged=$(whiptail --menu "Container type" 10 58 2 \
    "1" "Unprivileged (recommended)" \
    "0" "Privileged" \
    --title "Container Type" 3>&1 1>&2 2>&3) || var_unprivileged=1

  var_tags=$(whiptail --inputbox "Tags (comma separated)" 8 58 "$var_tags" --title "Proxmox Tags" 3>&1 1>&2 2>&3) || var_tags="ebook"
  var_mac=$(whiptail --inputbox "MAC Address (Leave blank for random)" 8 58 "$var_mac" --title "MAC Address" 3>&1 1>&2 2>&3) || var_mac=""
  var_root_password=$(whiptail --passwordbox "Root Password (Leave blank for passwordless)" 8 58 --title "Root Password" 3>&1 1>&2 2>&3) || var_root_password=""
  
  var_ssh=$(whiptail --menu "Enable Root SSH Access?" 10 58 2 \
    "0" "No (recommended)" \
    "1" "Yes" \
    --title "SSH Access" 3>&1 1>&2 2>&3) || var_ssh="0"

  while true; do
    CTID=$(whiptail --inputbox "Container ID (100–999999999)" 8 58 "$CTID" --title "Container ID" 3>&1 1>&2 2>&3) || break
    if ! [[ "$CTID" =~ ^[0-9]+$ ]] || [[ "$CTID" -lt 100 || "$CTID" -gt 999999999 ]]; then
      whiptail --msgbox "Invalid ID: must be a number between 100 and 999999999." 8 58 --title "Invalid Input"
      continue
    fi
    if pct status "$CTID" &>/dev/null || qm status "$CTID" &>/dev/null; then
      whiptail --msgbox "Container/VM ID ${CTID} is already in use. Choose another." 8 58 --title "ID In Use"
      continue
    fi
    break
  done
}

CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" \
  --title "${APP} LXC Setup" \
  --menu "Choose installation type:" 12 58 2 \
  "1" "Default settings (recommended)" \
  "2" "Advanced settings" \
  3>&1 1>&2 2>&3)

case "$CHOICE" in
  2) advanced_settings ;;
  *) msg_ok "Using default settings" ;;
esac

msg_ok "Container ID: ${BL}${CTID}${CL}"

STORAGE=$(pvesm status -content rootdir | awk 'NR>1 {print $1; exit}')
if [[ -z "$STORAGE" ]]; then
  msg_error "No suitable storage found."
  exit 1
fi
msg_ok "Storage: ${BL}${STORAGE}${CL}"

# -----------------------------------------------------------------------
# Download template
# -----------------------------------------------------------------------
TEMPLATE_STORAGE=$(pvesm status -content vztmpl | awk 'NR>1 {print $1; exit}')
TEMPLATE_STORAGE=${TEMPLATE_STORAGE:-local}

TEMPLATE="debian-${var_version}-standard_${var_version}.*_amd64.tar.zst"
TEMPLATE_FILE=$(pvesm list "$TEMPLATE_STORAGE" --content vztmpl 2>/dev/null | grep -o "debian-${var_version}-standard[^ ]*" | head -1)

if [[ -z "$TEMPLATE_FILE" ]]; then
  msg_info "Downloading Debian ${var_version} template..."
  pveam update &>/dev/null
  TEMPLATE_DL=$(pveam available --section system | grep "debian-${var_version}-standard" | sort -V | tail -1 | awk '{print $2}')
  pveam download "$TEMPLATE_STORAGE" "$TEMPLATE_DL" &>/dev/null
  TEMPLATE_FILE=$(pvesm list "$TEMPLATE_STORAGE" --content vztmpl 2>/dev/null | grep -o "debian-${var_version}-standard[^ ]*" | head -1)
  msg_ok "Downloaded template"
else
  msg_ok "Template already available"
fi

# -----------------------------------------------------------------------
# Create the LXC container
# -----------------------------------------------------------------------
msg_info "Creating LXC container ${CTID}..."

NET0="name=eth0,bridge=vmbr0,ip=dhcp"
if [[ -n "$var_mac" ]]; then
  NET0="${NET0},hwaddr=${var_mac}"
fi

PCT_OPTIONS=(
  --hostname "$var_hostname"
  --cores "$var_cpu"
  --memory "$var_ram"
  --rootfs "${STORAGE}:${var_disk}"
  --net0 "$NET0"
  --onboot 1
  --ostype "${var_os}"
  --tags "$var_tags"
  --unprivileged "$var_unprivileged"
  --features nesting=1
)

if [[ -n "$var_root_password" ]]; then
  PCT_OPTIONS+=(--password "$var_root_password")
fi

pct create "$CTID" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE_FILE}" "${PCT_OPTIONS[@]}" &>/dev/null
msg_ok "Created LXC container ${CTID}"

msg_info "Starting container..."
pct start "$CTID"
sleep 5
msg_ok "Container started"

# Set up SSH if requested
if [[ "$var_ssh" == "1" ]]; then
  msg_info "Setting up Root SSH access..."
  pct exec "$CTID" -- bash -c "apt-get update >/dev/null 2>&1 && apt-get install -y openssh-server >/dev/null 2>&1"
  pct exec "$CTID" -- sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config
  pct exec "$CTID" -- systemctl restart ssh
  msg_ok "SSH access enabled"
fi

# -----------------------------------------------------------------------
# Download and execute install scripts
# -----------------------------------------------------------------------
msg_info "Downloading community-scripts install functions..."
FUNCTIONS_FILE_PATH=$(curl -fsSL "$FUNCTIONS_URL")
msg_ok "Downloaded install functions"

msg_info "Downloading ${APP} install script..."
INSTALL_SCRIPT_TMP=$(mktemp /tmp/send2ereader-install-XXXXXX.sh)
curl -fsSL "$INSTALL_SCRIPT_URL" -o "$INSTALL_SCRIPT_TMP"
msg_ok "Downloaded install script"

msg_info "Pushing install script into container..."
pct push "$CTID" "$INSTALL_SCRIPT_TMP" /root/send2ereader-install.sh
rm -f "$INSTALL_SCRIPT_TMP"
pct exec "$CTID" -- chmod +x /root/send2ereader-install.sh
msg_ok "Pushed install script"

msg_info "Running ${APP} install script inside container..."
pct exec "$CTID" -- bash -c "export APP='${APP}'; export FUNCTIONS_FILE_PATH=$(printf '%q' "$FUNCTIONS_FILE_PATH"); bash /root/send2ereader-install.sh"
INSTALL_EXIT=$?

pct exec "$CTID" -- rm -f /root/send2ereader-install.sh &>/dev/null || true

if [[ $INSTALL_EXIT -ne 0 ]]; then
  msg_error "Install script failed. Check container ${CTID} logs."
  exit 1
fi
msg_ok "Install script completed"

IP=$(pct exec "$CTID" -- ip -4 addr show eth0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1)
IP="${IP:-<container-ip>}"

echo
msg_ok "Completed successfully!"
echo -e "${TAB}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${TAB}${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}  ${BL}http://${IP}:3001${CL}"
echo
CROSS="${RD}✗${CL}"
INFO="[i]"
TAB="  "

msg_info()  { echo -e "${TAB}${YW}[...] $1${CL}"; }
msg_ok()    { echo -e "${TAB}${CM} ${GN}$1${CL}"; }
msg_error() { echo -e "${TAB}${CROSS} ${RD}$1${CL}"; }

header_info() {
  clear
  cat <<"EOF"
   _____                 _  ____      ____                _
  / ____|               | ||___ \    |  _ \              | |
 | (___   ___ _ __   __| |  __) |___| |_) | ___  __ _  _| | ___ _ __
  \___ \ / _ \ '_ \ / _` | |__ < __|  _ < / _ \/ _` |/ _` |/ _ \ '__|
  ____) |  __/ | | | (_| | ___) \__ \ |_) |  __/ (_| | (_| |  __/ |
 |_____/ \___|_| |_|\__,_||____/|___/____/ \___|\__,_|\__,_|\___|_|

EOF
  echo -e "${BL}  Community-style LXC Script${CL} — ${GN}${APP}${CL}"
  echo
}

# -----------------------------------------------------------------------
# Pre-flight checks
# -----------------------------------------------------------------------
if ! command -v pveversion &>/dev/null; then
  msg_error "This script must be run on a Proxmox VE host."
  exit 1
fi

if [[ "$(id -u)" -ne 0 ]]; then
  msg_error "This script must be run as root."
  exit 1
fi

header_info

# -----------------------------------------------------------------------
# Pre-calculate suggested next CTID (used as default in advanced menu)
# -----------------------------------------------------------------------
CTID=$(pvesh get /cluster/nextid)

# -----------------------------------------------------------------------
# Interactive configuration menu (whiptail)
# -----------------------------------------------------------------------
function advanced_settings() {
  var_cpu=$(whiptail --inputbox "Number of CPU cores" 8 58 "$var_cpu" \
    --title "CPU Cores" 3>&1 1>&2 2>&3) || var_cpu=1

  var_ram=$(whiptail --inputbox "Amount of RAM (MB)" 8 58 "$var_ram" \
    --title "RAM (MB)" 3>&1 1>&2 2>&3) || var_ram=512

  var_disk=$(whiptail --inputbox "Disk size (GB)" 8 58 "$var_disk" \
    --title "Disk Size (GB)" 3>&1 1>&2 2>&3) || var_disk=4

  var_hostname=$(whiptail --inputbox "Container hostname" 8 58 "$var_hostname" \
    --title "Hostname" 3>&1 1>&2 2>&3) || var_hostname=$NSAPP

  var_unprivileged=$(whiptail --menu "Container type" 10 58 2 \
    "1" "Unprivileged (recommended)" \
    "0" "Privileged" \
    --title "Container Type" 3>&1 1>&2 2>&3) || var_unprivileged=1

  # CTID with validation
  while true; do
    CTID=$(whiptail --inputbox "Container ID (100–999999999)" 8 58 "$CTID" \
      --title "Container ID" 3>&1 1>&2 2>&3) || break
    # Must be a number in valid PVE range
    if ! [[ "$CTID" =~ ^[0-9]+$ ]] || [[ "$CTID" -lt 100 || "$CTID" -gt 999999999 ]]; then
      whiptail --msgbox "Invalid ID: must be a number between 100 and 999999999." 8 58 --title "Invalid Input"
      continue
    fi
    # Must not already be in use
    if pct status "$CTID" &>/dev/null || qm status "$CTID" &>/dev/null; then
      whiptail --msgbox "Container/VM ID ${CTID} is already in use. Choose another." 8 58 --title "ID In Use"
      continue
    fi
    break
  done
}

CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" \
  --title "${APP} LXC Setup" \
  --menu "Choose installation type:" 12 58 2 \
  "1" "Default settings (recommended)" \
  "2" "Advanced settings" \
  3>&1 1>&2 2>&3)

case "$CHOICE" in
  2) advanced_settings ;;
  *) msg_ok "Using default settings" ;;
esac

msg_ok "Container ID: ${BL}${CTID}${CL}"

# Pick first available local storage
STORAGE=$(pvesm status -content rootdir | awk 'NR>1 {print $1; exit}')
if [[ -z "$STORAGE" ]]; then
  msg_error "No suitable storage found. Please configure a storage with 'rootdir' content type."
  exit 1
fi
msg_ok "Storage: ${BL}${STORAGE}${CL}"

# -----------------------------------------------------------------------
# Download template
# -----------------------------------------------------------------------
TEMPLATE_STORAGE=$(pvesm status -content vztmpl | awk 'NR>1 {print $1; exit}')
if [[ -z "$TEMPLATE_STORAGE" ]]; then
  TEMPLATE_STORAGE="local"
fi

TEMPLATE="debian-${var_version}-standard_${var_version}.*_amd64.tar.zst"
TEMPLATE_FILE=$(pvesm list "$TEMPLATE_STORAGE" --content vztmpl 2>/dev/null | grep -o "debian-${var_version}-standard[^ ]*" | head -1)

if [[ -z "$TEMPLATE_FILE" ]]; then
  msg_info "Downloading Debian ${var_version} template..."
  pveam update &>/dev/null
  TEMPLATE_DL=$(pveam available --section system | grep "debian-${var_version}-standard" | sort -V | tail -1 | awk '{print $2}')
  if [[ -z "$TEMPLATE_DL" ]]; then
    msg_error "Could not find Debian ${var_version} template."
    exit 1
  fi
  pveam download "$TEMPLATE_STORAGE" "$TEMPLATE_DL" &>/dev/null
  TEMPLATE_FILE=$(pvesm list "$TEMPLATE_STORAGE" --content vztmpl 2>/dev/null | grep -o "debian-${var_version}-standard[^ ]*" | head -1)
  msg_ok "Downloaded template: ${BL}${TEMPLATE_FILE}${CL}"
else
  msg_ok "Template already available: ${BL}${TEMPLATE_FILE}${CL}"
fi

# -----------------------------------------------------------------------
# Create the LXC container
# -----------------------------------------------------------------------
msg_info "Creating LXC container ${CTID}..."
pct create "$CTID" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE_FILE}" \
  --hostname "$var_hostname" \
  --cores "$var_cpu" \
  --memory "$var_ram" \
  --rootfs "${STORAGE}:${var_disk}" \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --onboot 1 \
  --ostype "${var_os}" \
  --tags "$var_tags" \
  --unprivileged "$var_unprivileged" \
  --features nesting=1 \
  &>/dev/null
msg_ok "Created LXC container ${CTID}"

# -----------------------------------------------------------------------
# Start container
# -----------------------------------------------------------------------
msg_info "Starting container..."
pct start "$CTID"
sleep 5
msg_ok "Container started"

# -----------------------------------------------------------------------
# Download install.func and install script ON THE HOST (curl is available
# here), then push the script into the container and execute it.
# This avoids the "curl: command not found" error in a fresh Debian CT.
# -----------------------------------------------------------------------
msg_info "Downloading community-scripts install functions..."
FUNCTIONS_FILE_PATH=$(curl -fsSL "$FUNCTIONS_URL")
if [[ -z "$FUNCTIONS_FILE_PATH" || ${#FUNCTIONS_FILE_PATH} -lt 100 ]]; then
  msg_error "Failed to download install functions from: $FUNCTIONS_URL"
  exit 1
fi
msg_ok "Downloaded install functions"

msg_info "Downloading ${APP} install script..."
INSTALL_SCRIPT_TMP=$(mktemp /tmp/send2ereader-install-XXXXXX.sh)
curl -fsSL "$INSTALL_SCRIPT_URL" -o "$INSTALL_SCRIPT_TMP"
if [[ ! -s "$INSTALL_SCRIPT_TMP" ]]; then
  msg_error "Failed to download install script from: $INSTALL_SCRIPT_URL"
  rm -f "$INSTALL_SCRIPT_TMP"
  exit 1
fi
msg_ok "Downloaded install script"

msg_info "Pushing install script into container..."
pct push "$CTID" "$INSTALL_SCRIPT_TMP" /root/send2ereader-install.sh
rm -f "$INSTALL_SCRIPT_TMP"
pct exec "$CTID" -- chmod +x /root/send2ereader-install.sh
msg_ok "Pushed install script"

msg_info "Running ${APP} install script inside container..."
pct exec "$CTID" -- bash -c \
  "export APP='${APP}'; export FUNCTIONS_FILE_PATH=$(printf '%q' "$FUNCTIONS_FILE_PATH"); bash /root/send2ereader-install.sh"
INSTALL_EXIT=$?

# Cleanup the install script from inside the container
pct exec "$CTID" -- rm -f /root/send2ereader-install.sh &>/dev/null || true

if [[ $INSTALL_EXIT -ne 0 ]]; then
  msg_error "Install script failed (exit code: ${INSTALL_EXIT}). Check container ${CTID} logs."
  exit 1
fi
msg_ok "Install script completed"

# -----------------------------------------------------------------------
# Get container IP and display summary
# -----------------------------------------------------------------------
IP=$(pct exec "$CTID" -- ip -4 addr show eth0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1)
IP="${IP:-<container-ip>}"

echo
msg_ok "Completed successfully!"
echo -e "${TAB}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${TAB}${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}  ${BL}http://${IP}:3001${CL}"
echo
