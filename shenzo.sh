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

# ---------- Auto add: password-gated sshx terminal (NuflixCloud banner) ----------
# 1) writes nuflix-login.sh next to the bot code
# 2) patches lxcManager.js -> getSshxLink() pushes it into the container and
#    starts sshx with:  sshx --shell /usr/local/bin/nuflix-login
# Fail-closed: if the login script cannot be pushed, no sshx link is created.
# Guarded: if the bot code looks different, it skips safely.
patch_sshx_login() {
  if [ ! -f lxcManager.js ]; then
    fail "SSHX patch skipped: lxcManager.js not found."
    return 0
  fi

  if grep -q "nuflix-login" lxcManager.js; then
    echo -e "${GREEN}[i] SSHX patch: already applied.${NC}"
    return 0
  fi

  local n_nohup n_out
  n_nohup=$(grep -c "nohup sshx > /tmp/.nuflixcloud_sshx.log" lxcManager.js)
  n_out=$(grep -c "const out = run(LXC_BIN, \['exec', containerName, '--', 'bash', '-c', script\], { timeout: 45_000 });" lxcManager.js)
  if [ "$n_nohup" -ne 1 ] || [ "$n_out" -ne 1 ]; then
    fail "SSHX patch skipped: getSshxLink() looks different in this bot version."
    return 0
  fi

  step "Adding NuflixCloud sshx login (password + banner)..."
  cp lxcManager.js lxcManager.js.bak

  cat > nuflix-login.sh <<'NUFLIX_LOGIN_EOF'
#!/bin/bash
# ==================================================
#  nuflix-login.sh — NuflixCloud secure terminal gate
#  Used as the sshx shell:
#      sshx --shell /usr/local/bin/nuflix-login
#  Flow: ask password -> (root password of this VPS, same one shown on
#        Discord) -> NuflixCloud banner + welcome -> normal bash shell.
# ==================================================

LOGIN_USER="${NUFLIX_USER:-root}"
MAX_TRIES=3
export TERM="${TERM:-xterm-256color}"

PINK=$'\e[1;38;5;213m'
GREEN=$'\e[1;32m'
RED=$'\e[1;31m'
CYAN=$'\e[1;36m'
NC=$'\e[0m'

trap 'echo; exit 1' INT
trap '' TSTP

# Password checker that ships with Ubuntu (libpam-modules). Works with any
# hash type, and always checks the CURRENT password of the user.
CHK=/usr/sbin/unix_chkpwd
[ -x "$CHK" ] || CHK=/sbin/unix_chkpwd
if [ ! -x "$CHK" ]; then
  echo "${RED}[!] Password checker missing (libpam-modules). Access denied.${NC}"
  sleep 2
  exit 1
fi

check_password() {
  printf '%s\0' "$1" | "$CHK" "$LOGIN_USER" nonull >/dev/null 2>&1
}

term_cols() {
  local c
  c=$(tput cols 2>/dev/null)
  [[ "$c" =~ ^[0-9]+$ ]] || c=$(stty size 2>/dev/null | cut -d' ' -f2)
  [[ "$c" =~ ^[0-9]+$ ]] || c=80
  echo "$c"
}

show_banner() {
  clear
  printf '%s' "$PINK"
  if [ "$(term_cols)" -ge 90 ]; then
    cat <<'ART'
███╗   ██╗██╗   ██╗███████╗██╗     ██╗██╗  ██╗ ██████╗██╗      ██████╗ ██╗   ██╗██████╗ 
████╗  ██║██║   ██║██╔════╝██║     ██║╚██╗██╔╝██╔════╝██║     ██╔═══██╗██║   ██║██╔══██╗
██╔██╗ ██║██║   ██║█████╗  ██║     ██║ ╚███╔╝ ██║     ██║     ██║   ██║██║   ██║██║  ██║
██║╚██╗██║██║   ██║██╔══╝  ██║     ██║ ██╔██╗ ██║     ██║     ██║   ██║██║   ██║██║  ██║
██║ ╚████║╚██████╔╝██║     ███████╗██║██╔╝ ██╗╚██████╗███████╗╚██████╔╝╚██████╔╝██████╔╝
╚═╝  ╚═══╝ ╚═════╝ ╚═╝     ╚══════╝╚═╝╚═╝  ╚═╝ ╚═════╝╚══════╝ ╚═════╝  ╚═════╝ ╚═════╝ 
ART
  else
    # narrow screens (phones): two lines
    cat <<'ART'
███╗   ██╗██╗   ██╗███████╗██╗     ██╗██╗  ██╗
████╗  ██║██║   ██║██╔════╝██║     ██║╚██╗██╔╝
██╔██╗ ██║██║   ██║█████╗  ██║     ██║ ╚███╔╝ 
██║╚██╗██║██║   ██║██╔══╝  ██║     ██║ ██╔██╗ 
██║ ╚████║╚██████╔╝██║     ███████╗██║██╔╝ ██╗
╚═╝  ╚═══╝ ╚═════╝ ╚═╝     ╚══════╝╚═╝╚═╝  ╚═╝
 ██████╗██╗      ██████╗ ██╗   ██╗██████╗ 
██╔════╝██║     ██╔═══██╗██║   ██║██╔══██╗
██║     ██║     ██║   ██║██║   ██║██║  ██║
██║     ██║     ██║   ██║██║   ██║██║  ██║
╚██████╗███████╗╚██████╔╝╚██████╔╝██████╔╝
 ╚═════╝╚══════╝ ╚═════╝  ╚═════╝ ╚═════╝ 
ART
  fi
  printf '%s\n' "$NC"
  printf '%s🚀 Welcome To NuflixCloud Datacenter%s\n\n' "$GREEN" "$NC"
}

# ---------- Password prompt ----------
clear
printf '%s🔒 NuflixCloud Secure Terminal%s\n\n' "$CYAN" "$NC"

ok=0
for ((i = 1; i <= MAX_TRIES; i++)); do
  printf 'Password: '
  IFS= read -rs pw || { echo; break; }
  echo
  if check_password "$pw"; then
    ok=1
    break
  fi
  printf '%sIncorrect password. (%d/%d)%s\n' "$RED" "$i" "$MAX_TRIES" "$NC"
  sleep 2
done
unset pw

if [ "$ok" -ne 1 ]; then
  printf '%sAccess denied.%s\n' "$RED" "$NC"
  sleep 1
  exit 1
fi

show_banner
cd "$(getent passwd "$LOGIN_USER" | cut -d: -f6)" 2>/dev/null || cd /
exec bash -l
NUFLIX_LOGIN_EOF
  chmod +x nuflix-login.sh

  # (a) start sshx with the login script as its shell
  sed -i 's|nohup sshx > /tmp/.nuflixcloud_sshx.log|nohup sshx --shell /usr/local/bin/nuflix-login > /tmp/.nuflixcloud_sshx.log|' lxcManager.js

  # (b) push the login script into the container right before sshx is started
  local ins_file line
  ins_file=$(mktemp)
  cat > "$ins_file" <<'INSERT_EOF'
  // NuflixCloud: password-gated sshx terminal (fail closed if the login script can't be installed)
  try {
    run(LXC_BIN, ['file', 'push', require('path').join(__dirname, 'nuflix-login.sh'), `${containerName}/usr/local/bin/nuflix-login`, '--mode', '755']);
  } catch (e) {
    console.error('nuflix-login push failed:', e.message);
    return null;
  }
INSERT_EOF
  line=$(grep -n "const out = run(LXC_BIN, \['exec', containerName, '--', 'bash', '-c', script\], { timeout: 45_000 });" lxcManager.js | cut -d: -f1)
  sed -i "$((line - 1))r $ins_file" lxcManager.js
  rm -f "$ins_file"

  # Safety net: if lxcManager.js no longer parses, roll everything back
  if command -v node >/dev/null 2>&1 && ! node --check lxcManager.js 2>/dev/null; then
    fail "SSHX patch broke lxcManager.js, rolling back."
    mv -f lxcManager.js.bak lxcManager.js
    rm -f nuflix-login.sh
    return 0
  fi

  rm -f lxcManager.js.bak
  echo -e "${GREEN}[✓] SSHX login patch applied.${NC}"
}

# ---------- Bot installer ----------
# usage: install_bot <folder> <zip-name> <url> <status: yes|no>
#   status=yes -> also adds the DND + rotating status (only used for V2)
install_bot() {
  local DIR="$1" ZIP="$2" URL="$3" STATUS="${4:-no}"
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
  patch_sshx_login

  if [ "$STATUS" = "yes" ]; then
    patch_presence
  fi

  step "cp .env.example .env"
  if [ -f .env ]; then
    echo -e "${GREEN}[i] .env already exists, keeping it.${NC}"
  elif [ -f .env.example ]; then
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

# ---------- Standalone patch mode ----------
# Usage: bash <(curl -s URL) patch-sshx /root/shenzov1bot
if [ "$1" = "patch-sshx" ]; then
  cd "${2:-.}" || { fail "Folder not found: $2"; exit 1; }
  patch_sshx_login
  exit 0
fi

# ---------- Main loop ----------
while true; do
  banner
  echo -en "${GREEN}Shenzo-INS > ${NC}"
  read -r choice

  case "$choice" in
    1) install_bot "shenzov1bot" "vpsv1.zip" "$V1_URL" "no" ;;
    2) install_bot "shenzov2bot" "vpsv2.zip" "$V2_URL" "yes" ;;
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
