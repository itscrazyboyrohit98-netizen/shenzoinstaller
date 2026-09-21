#!/bin/bash
# ==================================================
#   SHENZO BOT INSTALLER
#   Run: bash <(curl -s https://raw.githubusercontent.com/itscrazyboyrohit98-netizen/shenzoinstaller/refs/heads/main/shenzo.sh)
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

# ---------- Auto fix: "Failed to connect to bus" (hostnamectl) ----------
# hostnamectl needs D-Bus, which is not ready inside a fresh LXC container.
# Replace it with a plain command that works without D-Bus.
patch_hostname_fix() {
  local files
  files=$(grep -rl "hostnamectl set-hostname" . \
    --include="*.js" --include="*.mjs" --include="*.cjs" --include="*.ts" \
    --exclude-dir=node_modules 2>/dev/null)

  if [ -z "$files" ]; then
    echo -e "${GREEN}[i] Hostname fix: nothing to patch.${NC}"
    return 0
  fi

  step "Applying hostname fix (D-Bus error)..."
  while read -r f; do
    sed -i 's|hostnamectl set-hostname \([A-Za-z0-9_.${}-]*\)|echo \1 > /etc/hostname \&\& hostname \1|g' "$f"
    echo -e "${GREEN}[✓] Patched: $f${NC}"
  done <<< "$files"
}

# ---------- Auto add: rotating status + DND ----------
# Adds presence.js and hooks it into the bot's "ready" event.
#   Watching: 🟢 X Running | 🟡 Y Created | 🔴 Z Suspended   (10s)
#   Custom  : Created By - Shenzo                            (10s)
#   Status  : DND
# Every step is guarded: if the bot code looks different, it skips safely.
patch_presence() {
  if [ ! -f index.js ] || [ ! -f vpsStore.js ]; then
    fail "Status patch skipped: index.js / vpsStore.js not found."
    return 0
  fi

  if grep -q "startPresence" index.js; then
    echo -e "${GREEN}[i] Status patch: already applied.${NC}"
    return 0
  fi

  if ! grep -q "getAllRecords" vpsStore.js || ! grep -q "GatewayIntentBits" index.js; then
    fail "Status patch skipped: unexpected bot code (needs discord.js v14 + vpsStore.getAllRecords)."
    return 0
  fi

  local line
  line=$(grep -nE "client\.(once|on)\(\s*(['\"](ready|clientReady)['\"]|Events\.(ClientReady|Ready))" index.js | head -n1 | cut -d: -f1)
  if [ -z "$line" ] || ! sed -n "${line}p" index.js | grep -qE "\{\s*$"; then
    fail "Status patch skipped: could not find the 'ready' event in index.js."
    return 0
  fi

  if grep -qE "setActivity|setPresence" index.js; then
    fail "Note: index.js already sets a presence. The new status will override it every 10s."
  fi

  step "Adding rotating status (DND + Created By - Shenzo)..."
  cp index.js index.js.bak

  cat > presence.js <<'PRESENCE_EOF'
// presence.js — bot status: DND + rotates every 10 seconds
const fs = require('fs');
const { execFile } = require('child_process');
const { ActivityType } = require('discord.js');
const store = require('./vpsStore');

const LXC_BIN = fs.existsSync('/snap/bin/lxc') ? '/snap/bin/lxc' : 'lxc';
const INTERVAL_MS = 10 * 1000;
const CREATED_BY_TEXT = 'Created By - Shenzo';

let lastCounts = { running: 0, created: 0, suspended: 0 };

function listRunningNames() {
  return new Promise((resolve, reject) => {
    execFile(
      LXC_BIN,
      ['list', '--format', 'json'],
      { timeout: 8000, maxBuffer: 10 * 1024 * 1024 },
      (err, stdout) => {
        if (err) return reject(err);
        try {
          const list = JSON.parse(stdout);
          resolve(new Set(list.filter((c) => c.status === 'Running').map((c) => c.name)));
        } catch (e) {
          reject(e);
        }
      }
    );
  });
}

async function getCounts() {
  const records = store.getAllRecords();
  const created = records.length;
  const suspended = records.filter((v) => v.suspended).length;

  let running = lastCounts.running;
  try {
    const runningNames = await listRunningNames();
    running = records.filter((v) => runningNames.has(v.containerName)).length;
  } catch (e) {
    console.error('presence: lxc list failed:', e.message);
  }

  lastCounts = { running, created, suspended };
  return lastCounts;
}

function startPresence(client) {
  let showCounts = true;

  const update = async () => {
    try {
      if (showCounts) {
        const c = await getCounts();
        client.user.setPresence({
          status: 'dnd',
          activities: [
            {
              name: `🟢 ${c.running} Running | 🟡 ${c.created} Created | 🔴 ${c.suspended} Suspended`,
              type: ActivityType.Watching,
            },
          ],
        });
      } else {
        client.user.setPresence({
          status: 'dnd',
          activities: [
            { name: 'Custom Status', state: CREATED_BY_TEXT, type: ActivityType.Custom },
          ],
        });
      }
    } catch (e) {
      console.error('presence error:', e.message);
    }
    showCounts = !showCounts;
  };

  update();
  setInterval(update, INTERVAL_MS);
}

module.exports = { startPresence };
PRESENCE_EOF

  sed -i "${line}a\\  require('./presence').startPresence(client);" index.js

  # Safety net: if index.js no longer parses, roll everything back
  if command -v node >/dev/null 2>&1 && ! node --check index.js 2>/dev/null; then
    fail "Status patch broke index.js, rolling back."
    mv -f index.js.bak index.js
    rm -f presence.js
    return 0
  fi

  rm -f index.js.bak
  echo -e "${GREEN}[✓] Status patch applied.${NC}"
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

  patch_hostname_fix
  patch_presence

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
