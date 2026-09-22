#!/bin/bash
# ==================================================
#   SHENZO BOT INSTALLER (customized)
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

# ---------- Runtime / branding state (set per install by ask_hosting_name) ----------
HOSTING_NAME=""
HOSTING_NAME_SLUG=""

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

# sed-escape a string for safe use inside s/// (escapes & \ and /)
sed_escape() { printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'; }

# ---------- Ask hosting name (runs BEFORE lxd init) ----------
ask_hosting_name() {
  echo
  echo -e "${CYAN}--- Hosting Branding ---${NC}"
  while [ -z "$HOSTING_NAME" ]; do
    read -rp "Your Hosting Name > " HOSTING_NAME
  done

  # Safe slug: letters/digits/dash/underscore only, used for pm2 process name
  HOSTING_NAME_SLUG=$(echo "$HOSTING_NAME" | tr -cs 'A-Za-z0-9_-' '-' | sed 's/^-*//; s/-*$//')
  [ -z "$HOSTING_NAME_SLUG" ] && HOSTING_NAME_SLUG="hosting-bot"

  echo "$HOSTING_NAME" > .hosting_name
  echo -e "${GREEN}[i] Hosting name set to: $HOSTING_NAME (process name: $HOSTING_NAME_SLUG)${NC}"
}

# ---------- Apply the hosting name wherever the old "NuflixCloud"/"Shenzo"
# branding was hardcoded (sshx login banner, presence status, share DMs).
# Safe: only touches files that exist, does nothing if HOSTING_NAME is empty. ----------
apply_branding() {
  [ -z "$HOSTING_NAME" ] && return 0
  local esc
  esc=$(sed_escape "$HOSTING_NAME")

  local f
  for f in nuflix-login.sh index.js presence.js; do
    [ -f "$f" ] || continue
    sed -i "s/NuflixCloud/${esc}/g; s/Shenzo/${esc}/g" "$f"
  done
  echo -e "${GREEN}[✓] Branding applied to sshx login / status / share messages.${NC}"
}

# ---------- .env questions (Discord Bot Token, Client ID, Guild ID, Command Channel ID) ----------
# NOTE: key names below (BOT_TOKEN / CLIENT_ID / GUILD_ID / COMMAND_CHANNEL_ID) are the
# common ones for this kind of bot. If your .env.example uses different key names
# (e.g. DISCORD_TOKEN, GUILDID, LOG_CHANNEL_ID), open .env once after this and rename
# to match, or tell me the exact keys and I'll adjust this function.
configure_env() {
  [ -f .env ] || { fail ".env not found, skipping env questions."; return 0; }

  echo
  echo -e "${CYAN}--- Discord Bot Configuration ---${NC}"
  local token clientid guildid chanid

  read -rp "Discord Bot Token       > " token
  read -rp "Client ID                > " clientid
  read -rp "Guild ID                 > " guildid
  read -rp "Command Channel ID       > " chanid

  set_env() {
    local key="$1" val="$2"
    if grep -q "^${key}=" .env 2>/dev/null; then
      sed -i "s|^${key}=.*|${key}=${val}|" .env
    else
      echo "${key}=${val}" >> .env
    fi
  }

  set_env "BOT_TOKEN" "$token"
  set_env "CLIENT_ID" "$clientid"
  set_env "GUILD_ID" "$guildid"
  set_env "COMMAND_CHANNEL_ID" "$chanid"

  echo -e "${GREEN}[✓] .env updated.${NC}"
}

# ---------- After lxd init: deploy commands + start with pm2 under the hosting name ----------
finalize_start() {
  if ! command -v pm2 >/dev/null 2>&1; then
    step "pm2 not found, installing globally via npm..."
    npm install -g pm2 || { fail "pm2 install failed, start the bot manually."; return 1; }
  fi

  if [ -f deploy-commands.js ]; then
    step "Deploying slash commands (node deploy-commands.js)..."
    node deploy-commands.js || fail "deploy-commands.js failed, check your .env values."
  else
    fail "deploy-commands.js not found, skipping command deploy."
  fi

  if [ -f index.js ]; then
    step "Starting bot with pm2 as '$HOSTING_NAME_SLUG'..."
    pm2 start index.js --name "$HOSTING_NAME_SLUG"
    pm2 save
  else
    fail "index.js not found, cannot start with pm2."
  fi
}

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

  step "Adding rotating status (DND + Created By - <hosting name>)..."
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

  if command -v node >/dev/null 2>&1 && ! node --check index.js 2>/dev/null; then
    fail "Status patch broke index.js, rolling back."
    mv -f index.js.bak index.js
    rm -f presence.js
    return 0
  fi

  rm -f index.js.bak
  echo -e "${GREEN}[✓] Status patch applied.${NC}"
}

# ---------- Auto add: password-gated sshx terminal (branded banner) ----------
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

  step "Adding password-gated sshx login (banner will use your hosting name)..."
  cp lxcManager.js lxcManager.js.bak

  cat > nuflix-login.sh <<'NUFLIX_LOGIN_EOF'
#!/bin/bash
# ==================================================
#  nuflix-login.sh — secure terminal gate
#  Used as the sshx shell:
#      sshx --shell /usr/local/bin/nuflix-login
#  Flow: ask password -> (root password of this VPS, same one shown on
#        Discord) -> welcome banner -> normal bash shell.
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
  printf '========================================\n'
  printf '   NuflixCloud Datacenter\n'
  printf '========================================\n'
  printf '%s\n' "$NC"
  printf '%s🚀 Welcome To NuflixCloud Datacenter%s\n\n' "$GREEN" "$NC"
}

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

  sed -i 's|nohup sshx > /tmp/.nuflixcloud_sshx.log|nohup sshx --shell /usr/local/bin/nuflix-login > /tmp/.nuflixcloud_sshx.log|' lxcManager.js

  local ins_file line
  ins_file=$(mktemp)
  cat > "$ins_file" <<'INSERT_EOF'
  // Password-gated sshx terminal (fail closed if the login script can't be installed)
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

  if command -v node >/dev/null 2>&1 && ! node --check lxcManager.js 2>/dev/null; then
    fail "SSHX patch broke lxcManager.js, rolling back."
    mv -f lxcManager.js.bak lxcManager.js
    rm -f nuflix-login.sh
    return 0
  fi

  rm -f lxcManager.js.bak
  echo -e "${GREEN}[✓] SSHX login patch applied.${NC}"
}

# ---------- Auto add (V2 only): /vps-share and /vps-unshare ----------
patch_share() {
  if [ ! -f index.js ] || [ ! -f commands.js ]; then
    fail "Share patch skipped: index.js / commands.js not found."
    return 0
  fi

  if grep -q "handleShare" index.js; then
    echo -e "${GREEN}[i] Share patch: already applied.${NC}"
    return 0
  fi

  local missing=0
  need() {
    local n
    n=$(grep -cF -- "$2" "$1")
    if [ "$n" -ne 1 ]; then
      fail "Share patch: expected exactly 1 match in $1 for: $2 (found $n)"
      missing=1
    fi
  }
  need index.js "if (interaction.commandName === 'vps-removeadmin') return handleRemoveAdmin(interaction);"
  need index.js "// ---- /vpshelp ----"
  need index.js "async function handleManage(interaction) {"
  need index.js "interaction.user.id !== record.ownerId && !admins.isAdmin(interaction.user.id)"
  need index.js "if (action === 'start') {"
  need index.js '${record.rootPassword}'
  need index.js "{ name: '/vpshelp', value: 'Shows this command list.' }"
  need commands.js ".setDescription('View and control your VPS')"
  need commands.js "].map((c) => c.toJSON());"
  if [ "$missing" -ne 0 ]; then
    fail "Share patch skipped: this bot version looks different (nothing was changed)."
    return 0
  fi

  step "Adding /vps-share and /vps-unshare (V2)..."
  local tmp
  tmp=$(mktemp -d)

  cat > "$tmp/dispatch.txt" <<'SHARE_DISPATCH_EOF'
    if (interaction.commandName === 'vps-share') return handleShare(interaction);
    if (interaction.commandName === 'vps-unshare') return handleUnshare(interaction);
SHARE_DISPATCH_EOF

  cat > "$tmp/handlers.txt" <<'SHARE_HANDLERS_EOF'
// =====================================================================
// VPS sharing  (/vps-share, /vps-unshare, /vps-manage vpsid)
// =====================================================================

function isSharedWith(record, userId) {
  return Array.isArray(record.sharedWith) && record.sharedWith.includes(userId);
}

function isOwnerOrAdmin(record, userId) {
  return userId === record.ownerId || admins.isAdmin(userId);
}

function shareSafePassword(record, userId) {
  return isOwnerOrAdmin(record, userId) ? record.rootPassword : 'Ask the VPS owner for the password';
}

function findVpsByNumber(number) {
  return store.getAllRecords().find((v) => Number(v.number) === Number(number)) || null;
}

async function handleShare(interaction) {
  const target = interaction.options.getUser('user', true);
  const vpsId = interaction.options.getInteger('vpsid', true);
  const record = findVpsByNumber(vpsId);

  if (!record || !isOwnerOrAdmin(record, interaction.user.id)) {
    return interaction.reply({
      content: `❌ VPS #${vpsId} was not found, or you are not its owner.`,
      ephemeral: true,
    });
  }
  if (target.bot) {
    return interaction.reply({ content: '❌ You cannot share a VPS with a bot.', ephemeral: true });
  }
  if (target.id === record.ownerId) {
    return interaction.reply({ content: `ℹ️ ${target} already owns VPS #${record.number}.`, ephemeral: true });
  }
  if (isSharedWith(record, target.id)) {
    return interaction.reply({
      content: `ℹ️ VPS #${record.number} is already shared with ${target}.`,
      ephemeral: true,
    });
  }

  const sharedWith = [...(record.sharedWith || []), target.id];
  store.updateRecord(record.containerName, { sharedWith });

  const embed = new EmbedBuilder()
    .setColor(0x57f287)
    .setTitle('🤝 VPS Shared')
    .setDescription(
      `VPS #${record.number} is now shared with ${target}.\n` +
        `They can start, stop and open the console from \`/vps-manage vpsid:${record.number}\`.\n` +
        `They cannot reinstall or share it. Give them the VPS password yourself (the bot does not send it).`
    )
    .setFooter(footerNow());
  await interaction.reply({ embeds: [embed] });

  await target
    .send(
      `🤝 <@${interaction.user.id}> shared NuflixCloud VPS #${record.number} with you. ` +
        `Use \`/vps-manage vpsid:${record.number}\` to manage it. Ask the VPS owner for the console password.`
    )
    .catch(() => {});
}

async function handleUnshare(interaction) {
  const target = interaction.options.getUser('user', true);
  const vpsId = interaction.options.getInteger('vpsid', true);
  const record = findVpsByNumber(vpsId);

  const leavingSelf = interaction.user.id === target.id;
  const allowed =
    record && (isOwnerOrAdmin(record, interaction.user.id) || (leavingSelf && isSharedWith(record, target.id)));
  if (!allowed) {
    return interaction.reply({
      content: `❌ VPS #${vpsId} was not found, or you are not its owner.`,
      ephemeral: true,
    });
  }
  if (!isSharedWith(record, target.id)) {
    return interaction.reply({
      content: `ℹ️ VPS #${record.number} is not shared with ${target}.`,
      ephemeral: true,
    });
  }

  store.updateRecord(record.containerName, {
    sharedWith: record.sharedWith.filter((id) => id !== target.id),
  });

  const embed = new EmbedBuilder()
    .setColor(0xed4245)
    .setTitle('🔒 VPS Unshared')
    .setDescription(`${target} no longer has access to VPS #${record.number}.`)
    .setFooter(footerNow());
  await interaction.reply({ embeds: [embed] });

  if (!leavingSelf) {
    await target
      .send(`🔒 Your access to NuflixCloud VPS #${record.number} has been removed.`)
      .catch(() => {});
  }
}

async function handleManageShared(interaction, vpsId) {
  const record = findVpsByNumber(vpsId);
  const uid = interaction.user.id;
  if (!record || !(isOwnerOrAdmin(record, uid) || isSharedWith(record, uid))) {
    return interaction.reply({
      content: `❌ VPS #${vpsId} was not found, or it is not shared with you.`,
      ephemeral: true,
    });
  }
  const { embed, rows } = await buildManageCard(record);
  return interaction.reply({ embeds: [embed], components: rows });
}

SHARE_HANDLERS_EOF

  cat > "$tmp/manage_hook.txt" <<'SHARE_MANAGE_EOF'
  // /vps-manage vpsid:<number> opens a VPS that was shared with you
  const sharedVpsId = interaction.options.getInteger('vpsid');
  if (sharedVpsId !== null) return handleManageShared(interaction, sharedVpsId);

SHARE_MANAGE_EOF

  cat > "$tmp/reinstall_guard.txt" <<'SHARE_GUARD_EOF'
  // only the owner (or an admin) can reinstall
  if (action === 'reinstall' && !isOwnerOrAdmin(record, interaction.user.id)) {
    return interaction.reply({ content: '❌ Only the VPS owner can reinstall this VPS.', ephemeral: true });
  }

SHARE_GUARD_EOF

  cat > "$tmp/help_fields.txt" <<'SHARE_HELP_EOF'
      {
        name: '/vps-share',
        value:
          'Shares your VPS with another user so they can start, stop and open the console. **VPS owner / admin only.**\nThey open it with `/vps-manage vpsid:<number>`.\nOptions: `user`, `vpsid` (VPS number)',
      },
      {
        name: '/vps-unshare',
        value:
          'Stops sharing a VPS with a user (a shared user can also remove themselves).\nOptions: `user`, `vpsid`',
      },
SHARE_HELP_EOF

  cat > "$tmp/cmd_manage_opt.txt" <<'SHARE_CMDOPT_EOF'
    .addIntegerOption((o) =>
      o
        .setName('vpsid')
        .setDescription('Open a VPS that was shared with you (VPS number)')
        .setRequired(false)
        .setMinValue(1)
    )
SHARE_CMDOPT_EOF

  cat > "$tmp/cmd_new.txt" <<'SHARE_CMDNEW_EOF'
  new SlashCommandBuilder()
    .setName('vps-share')
    .setDescription('Share your VPS with another user (VPS owner / Admin only)')
    .addUserOption((o) =>
      o.setName('user').setDescription('The user to share the VPS with').setRequired(true)
    )
    .addIntegerOption((o) =>
      o.setName('vpsid').setDescription('The VPS number (e.g. 12 for VPS #12)').setRequired(true).setMinValue(1)
    ),

  new SlashCommandBuilder()
    .setName('vps-unshare')
    .setDescription('Stop sharing a VPS with a user (VPS owner / Admin, or the shared user)')
    .addUserOption((o) =>
      o.setName('user').setDescription('The user to remove').setRequired(true)
    )
    .addIntegerOption((o) =>
      o.setName('vpsid').setDescription('The VPS number').setRequired(true).setMinValue(1)
    ),

SHARE_CMDNEW_EOF

  insert_after()  { local ln; ln=$(grep -nF -- "$2" "$1" | head -n1 | cut -d: -f1); sed -i "${ln}r $3" "$1"; }
  insert_before() { local ln; ln=$(grep -nF -- "$2" "$1" | head -n1 | cut -d: -f1); sed -i "$((ln - 1))r $3" "$1"; }

  cp index.js "$tmp/index.js"
  cp commands.js "$tmp/commands.js"

  insert_after  "$tmp/index.js" "if (interaction.commandName === 'vps-removeadmin') return handleRemoveAdmin(interaction);" "$tmp/dispatch.txt"
  insert_before "$tmp/index.js" "// ---- /vpshelp ----" "$tmp/handlers.txt"
  insert_after  "$tmp/index.js" "async function handleManage(interaction) {" "$tmp/manage_hook.txt"
  insert_before "$tmp/index.js" "if (action === 'start') {" "$tmp/reinstall_guard.txt"
  insert_before "$tmp/index.js" "{ name: '/vpshelp', value: 'Shows this command list.' }" "$tmp/help_fields.txt"

  sed -i 's|interaction\.user\.id !== record\.ownerId && !admins\.isAdmin(interaction\.user\.id)|& \&\& !isSharedWith(record, interaction.user.id)|' "$tmp/index.js"
  sed -i 's|\${record\.rootPassword}|${shareSafePassword(record, interaction.user.id)}|' "$tmp/index.js"

  insert_after  "$tmp/commands.js" ".setDescription('View and control your VPS')" "$tmp/cmd_manage_opt.txt"
  insert_before "$tmp/commands.js" "].map((c) => c.toJSON());" "$tmp/cmd_new.txt"

  if command -v node >/dev/null 2>&1; then
    if ! node --check "$tmp/index.js" 2>/dev/null || ! node --check "$tmp/commands.js" 2>/dev/null; then
      fail "Share patch would break the bot, nothing was changed."
      rm -rf "$tmp"
      return 0
    fi
  fi

  cp "$tmp/index.js" index.js
  cp "$tmp/commands.js" commands.js
  rm -rf "$tmp"
  echo -e "${GREEN}[✓] Share patch applied (/vps-share, /vps-unshare).${NC}"
  echo -e "${YELLOW}[!] After setup run:  node deploy-commands.js   (so the new commands show up in Discord)${NC}"
}

# ---------- Bot installer ----------
# usage: install_bot <hidden-folder> <zip-name> <url> <v2-extras: yes|no>
install_bot() {
  local DIR="$1" ZIP="$2" URL="$3" STATUS="${4:-no}"
  local START_DIR="$PWD"

  # Reset per-run branding state
  HOSTING_NAME=""
  HOSTING_NAME_SLUG=""

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
    patch_share
  fi

  step "cp .env.example .env"
  if [ -f .env ]; then
    echo -e "${GREEN}[i] .env already exists, keeping it.${NC}"
  elif [ -f .env.example ]; then
    cp .env.example .env
  else
    fail ".env.example not found (check the zip's folder structure)"
  fi

  # Hosting name asked BEFORE lxd init, as requested
  ask_hosting_name
  apply_branding

  configure_env

  lxd_setup

  finalize_start

  cd "$START_DIR" || true
  echo
  echo -e "${GREEN}[✓] $HOSTING_NAME setup finished. Running under pm2 as '$HOSTING_NAME_SLUG'.${NC}"
  sleep 2
}

# ---------- Standalone patch mode ----------
case "$1" in
  patch-sshx|patch-status|patch-share|patch-v2)
    cd "${2:-.}" || { fail "Folder not found: $2"; exit 1; }
    case "$1" in
      patch-sshx)   patch_sshx_login ;;
      patch-status) patch_presence ;;
      patch-share)  patch_share ;;
      patch-v2)     patch_hostname_fix; patch_sshx_login; patch_presence; patch_share ;;
    esac
    exit 0
    ;;
esac

# ---------- Main loop ----------
# NOTE: folders start with "." so a plain `ls` (or most SFTP clients' default
# view) won't show them. `ls -a` / "show hidden files" will still reveal them —
# this is normal Unix hidden-file behaviour, not true invisibility.
while true; do
  banner
  echo -en "${GREEN}Shenzo-INS > ${NC}"
  read -r choice

  case "$choice" in
    1) install_bot ".shenzov1bot" "vpsv1.zip" "$V1_URL" "no" ;;
    2) install_bot ".shenzov2bot" "vpsv2.zip" "$V2_URL" "yes" ;;
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
