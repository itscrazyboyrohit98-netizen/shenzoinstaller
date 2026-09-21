#!/bin/bash
# ==================================================
#   SHENZO BOT INSTALLER
#   Run: bash <(curl -s https://shenzoinstaller.in)
# ==================================================

export PATH="$PATH:/snap/bin"

# ---------- Colors ----------
BLUE='\e[1;38;5;63m'
CYAN='\e[1;36m'
GREEN='\e[1;32m'
RED='\e[1;31m'
YELLOW='\e[1;33m'
WHITE='\e[1;37m'
NC='\e[0m'

# ---------- Bot Links ----------
V1_URL="https://files.catbox.moe/hmf75a.zip"
V2_URL="https://files.catbox.moe/nhbsd1.zip"

# Inner width of the boxes (banner is 51 chars wide)
W=49

# ---------- Root check ----------
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${RED}[!] Root access required. Run 'sudo -i' first, then run the command again.${NC}"
  exit 1
fi

# ---------- Box helpers ----------
hr() { for ((i = 0; i < W; i++)); do printf '═'; done; }

box_top()    { echo -e "${CYAN}╔$(hr)╗${NC}"; }
box_bottom() { echo -e "${CYAN}╚$(hr)╝${NC}"; }

box_line() {
  printf "${CYAN}║${WHITE}%-${W}s${CYAN}║${NC}\n" "$1"
}

box_center() {
  local text="$1"
  local left=$(( (W - ${#text}) / 2 ))
  local right=$(( W - ${#text} - left ))
  printf "${CYAN}║${WHITE}%*s%s%*s${CYAN}║${NC}\n" "$left" "" "$text" "$right" ""
}

# ---------- Banner + Menu ----------
banner() {
  clear
  echo -e "${BLUE}"
  cat <<'EOF'
███████╗██╗  ██╗███████╗███╗   ██╗███████╗ ██████╗ 
██╔════╝██║  ██║██╔════╝████╗  ██║╚══███╔╝██╔═══██╗
███████╗███████║█████╗  ██╔██╗ ██║  ███╔╝ ██║   ██║
╚════██║██╔══██║██╔══╝  ██║╚██╗██║ ███╔╝  ██║   ██║
███████║██║  ██║███████╗██║ ╚████║███████╗╚██████╔╝
╚══════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝╚══════╝ ╚═════╝ 
EOF
  echo -e "${NC}"
  box_top
  box_center "SHENZO BOT INSTALLER"
  box_bottom
  echo
  box_top
  box_line "  [1] Vps Bot V1"
  box_line "  [2] Vps Bot V2"
  box_line "  [0] Exit"
  box_bottom
  echo
}

# ---------- Helpers ----------
step() { echo -e "${YELLOW}[+] $*${NC}"; }
fail() { echo -e "${RED}[!] $*${NC}"; }
pause() { echo; read -rp "Press Enter to go back to the menu..." _; }

# ---------- LXD init (zfs -> else btrfs) ----------
lxd_setup() {
  if ! command -v lxd >/dev/null 2>&1; then
    step "LXD not found, installing via snap..."
    snap install lxd || { fail "LXD install failed"; return 1; }
  fi

  if modprobe zfs 2>/dev/null; then
    step "ZFS is available. Choose 'zfs' as the storage backend in lxd init."
  else
    step "ZFS not supported here, installing btrfs..."
    apt install btrfs-progs -y || { fail "btrfs install failed"; return 1; }
    echo -e "${GREEN}[i] Choose 'btrfs' as the storage backend in lxd init.${NC}"
  fi

  step "lxd init"
  lxd init
}

# ---------- Bot installer ----------
# usage: install_bot <folder> <zip-name> <url>
install_bot() {
  local DIR="$1" ZIP="$2" URL="$3"
  local START_DIR="$PWD"

  step "mkdir $DIR"
  mkdir -p "$DIR" || { fail "Could not create $DIR"; pause; return 1; }

  step "apt install unzip -y"
  apt install unzip -y || { fail "unzip install failed"; pause; return 1; }

  step "cd $DIR"
  cd "$DIR" || { fail "Could not enter $DIR"; pause; return 1; }

  step "wget -O $ZIP $URL"
  wget -O "$ZIP" "$URL" || { fail "Download failed"; cd "$START_DIR"; pause; return 1; }

  step "unzip $ZIP"
  unzip -o "$ZIP" || { fail "Unzip failed"; cd "$START_DIR"; pause; return 1; }

  step "rm $ZIP"
  rm -f "$ZIP"

  step "cp .env.example .env"
  if [ -f .env.example ]; then
    cp .env.example .env
  else
    fail ".env.example not found (check the zip's folder structure)"
  fi

  lxd_setup

  cd "$START_DIR" || true
  echo
  echo -e "${GREEN}[✓] $DIR setup finished.${NC}"
  pause
}

# ---------- Main loop ----------
while true; do
  banner
  echo -en "${GREEN}Shenzo-INS > ${NC}"
  read -r choice

  case "$choice" in
    1) install_bot "shenzov1bot" "vpsv1.zip" "$V1_URL" ;;
    2) install_bot "shenzov2bot" "vpsv2.zip" "$V2_URL" ;;
    0)
      echo -e "${CYAN}GoodBye...${NC}"
      exit 0
      ;;
    *)
      fail "Invalid option, choose 1, 2 or 0."
      sleep 1
      ;;
  esac
done
