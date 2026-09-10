#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#   ROBLOX AUTO REJOIN + AUTO SCREENSHOT + AUTO-DETECT
#   Platform : Termux (Android)
#   Requires : Root (Magisk/KernelSU)
#   Uses     : curl, su, screencap, uiautomator
#   Install  : bash <(curl -sL https://raw.githubusercontent.com/USER/REPO/main/install.sh)
#   Run      : rejoin   (or  ~/bin/rejoin.sh)
# ============================================================

# ---------- Colors ----------
R='\033[1;31m'; G='\033[1;32m'; Y='\033[1;33m'
B='\033[1;34m'; C='\033[1;36m'; W='\033[1;37m'; N='\033[0m'

ROBLOX_PKG="com.roblox.client"
CONFIG_FILE="$HOME/.rejoin_config"
SHOT_PATH="/sdcard/roblox_shot.png"
LOG_FILE="$HOME/rejoin.log"

# ------------------------------------------------------------
#  BANNER
# ------------------------------------------------------------
banner() {
    clear
    echo -e "${C}"
    echo "  ╔═══════════════════════════════════════════════════╗"
    echo "  ║   ROBLOX AUTO REJOIN + SCREENSHOT + AUTO-DETECT   ║"
    echo "  ║          Termux  •  Root  •  Discord Webhook      ║"
    echo "  ╚═══════════════════════════════════════════════════╝"
    echo -e "${N}"
}

# ------------------------------------------------------------
#  DEPENDENCY CHECK
# ------------------------------------------------------------
check_deps() {
    local missing=0
    for c in curl su screencap pidof uiautomator; do
        if ! command -v "$c" >/dev/null 2>&1; then
            echo -e "${R}[!] Missing: $c${N}"
            missing=1
        fi
    done
    if [ "$missing" = "1" ]; then
        echo -e "${Y}[i] Auto-installing dependencies...${N}"
        pkg install -y curl termux-api tsu coreutils procps >/dev/null 2>&1
    fi
}

check_root() {
    if ! su -c "id" >/dev/null 2>&1; then
        echo -e "${R}[!] Root access denied.${N}"
        echo -e "${Y}    Allow the su request sa Magisk/KernelSU manager.${N}"
        exit 1
    fi
}

# ------------------------------------------------------------
#  ROBLOX CONTROL
# ------------------------------------------------------------
kill_roblox() {
    su -c "am force-stop $ROBLOX_PKG" >/dev/null 2>&1
    sleep 2
}

launch_roblox() {
    local id="$1"
    su -c "am start -a android.intent.action.VIEW \
        -d 'roblox://experiences/start?placeId=$id' \
        -n $ROBLOX_PKG/com.roblox.client.startup.ActivitySplash" \
        >/dev/null 2>&1
}

# ------------------------------------------------------------
#  DETECTION HELPERS
# ------------------------------------------------------------
is_roblox_alive() {
    pidof "$ROBLOX_PKG" >/dev/null 2>&1
}

is_roblox_foreground() {
    local fg
    fg=$(su -c "dumpsys activity activities 2>/dev/null | grep -E 'mResumedActivity|ResumedActivity'" 2>/dev/null)
    [ -z "$fg" ] && fg=$(su -c "dumpsys window 2>/dev/null | grep mCurrentFocus" 2>/dev/null)
    echo "$fg" | grep -q "$ROBLOX_PKG"
}

is_disconnected() {
    local xml="/sdcard/.window_dump.xml"
    su -c "rm -f $xml; uiautomator dump $xml" >/dev/null 2>&1
    [ -f "$xml" ] || return 1
    if grep -qiE 'text="[^"]*(disconnect|reconnect|connection lost|something went wrong|error code)' "$xml" 2>/dev/null; then
        rm -f "$xml" 2>/dev/null
        return 0
    fi
    rm -f "$xml" 2>/dev/null
    return 1
}

is_playing() {
    is_roblox_alive && is_roblox_foreground && ! is_disconnected
}

# ------------------------------------------------------------
#  SCREENSHOT
# ------------------------------------------------------------
take_screenshot() {
    su -c "screencap -p" > "$SHOT_PATH" 2>/dev/null
    [ -s "$SHOT_PATH" ]
}

# ------------------------------------------------------------
#  DISCORD WEBHOOK (curl)
# ------------------------------------------------------------
send_webhook() {
    local url="$1" msg="$2" mention="$3" color="$4"
    [ ! -f "$SHOT_PATH" ] && return 1

    local ts
    ts=$(date +"%Y-%m-%d %H:%M:%S")
    local fname="roblox_$(date +%Y%m%d_%H%M%S).png"

    # ---- Build content ----
    local content="$msg"
    if [ "$mention" = "y" ]; then
        content="@everyone
$msg"
    fi
    content="${content//\"/\\\"}"
    content="${content//$'\n'/\\n}"

    # ---- Build rich embed ----
    local payload
    payload=$(cat <<EOF
{
  "content": "$content",
  "allowed_mentions": { "parse": ["everyone"] },
  "embeds": [{
    "title": "🎮 Roblox Status",
    "description": "$msg",
    "color": ${color:-3447003},
    "image": { "url": "attachment://$fname" },
    "footer": { "text": "Termux Auto-Rejoin • $ts" }
  }]
}
EOF
)

    # ---- POST via curl (multipart) ----
    curl -s -X POST "$url" \
        -H "Content-Type: multipart/form-data" \
        -F "file=@$SHOT_PATH;filename=$fname;type=image/png" \
        -F "payload_json=$payload" \
        >/dev/null 2>&1
}

# Text-only webhook (para sa status/disconnect alerts)
send_webhook_text() {
    local url="$1" msg="$2" mention="$3"
    [ -z "$url" ] && return 1

    local content="$msg"
    if [ "$mention" = "y" ]; then
        content="@everyone
$msg"
    fi
    content="${content//\"/\\\"}"
    content="${content//$'\n'/\\n}"

    local payload
    payload=$(printf '{"content":"%s","allowed_mentions":{"parse":["everyone"]}}' "$content")

    curl -s -X POST "$url" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        >/dev/null 2>&1
}

# ------------------------------------------------------------
#  CONFIG SAVE / LOAD
# ------------------------------------------------------------
save_config() {
    cat > "$CONFIG_FILE" <<EOF
GAME_ID="$1"
REJOIN_MIN="$2"
SHOT_MIN="$3"
DETECT_SEC="$4"
WEBHOOK="$5"
MENTION="$6"
EOF
}

load_config() {
    [ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE" || true
}

# ------------------------------------------------------------
#  SETUP MENU
# ------------------------------------------------------------
setup_menu() {
    banner
    load_config

    read -rp "$(echo -e ${W}"Game ID (placeId)${N} [${GAME_ID:-walang laman}]: ")" TMP
    GAME_ID="${TMP:-$GAME_ID}"

    read -rp "$(echo -e ${W}"Scheduled rejoin (minutes)${N} [${REJOIN_MIN:-10}]: ")" TMP
    REJOIN_MIN="${TMP:-${REJOIN_MIN:-10}}"

    read -rp "$(echo -e ${W}"Screenshot interval (minutes)${N} [${SHOT_MIN:-1}]: ")" TMP
    SHOT_MIN="${TMP:-${SHOT_MIN:-1}}"

    read -rp "$(echo -e ${W}"Auto-detect: seconds bago mag-rejoin kapag hindi playing${N} [${DETECT_SEC:-5}]: ")" TMP
    DETECT_SEC="${TMP:-${DETECT_SEC:-5}}"

    read -rp "$(echo -e ${W}"Discord webhook URL${N}: ")" TMP
    WEBHOOK="${TMP:-$WEBHOOK}"

    read -rp "$(echo -e ${W}"Mention @everyone? (y/n)${N} [${MENTION:-y}]: ")" TMP
    MENTION="${TMP:-${MENTION:-y}}"

    save_config "$GAME_ID" "$REJOIN_MIN" "$SHOT_MIN" "$DETECT_SEC" "$WEBHOOK" "$MENTION"

    echo
    echo -e "${G}┌── Settings ───────────────────────────────────┐${N}"
    echo -e "${G}│${N} Game ID            : $GAME_ID"
    echo -e "${G}│${N} Scheduled rejoin   : $REJOIN_MIN min"
    echo -e "${G}│${N} Screenshot         : $SHOT_MIN min"
    echo -e "${G}│${N} Auto-detect        : $DETECT_SEC sec"
    echo -e "${G}│${N} Mention @everyone  : $MENTION"
    echo -e "${G}│${N} Webhook            : ${WEBHOOK:0:55}..."
    echo -e "${G}└───────────────────────────────────────────────┘${N}"
    echo

    read -rp "$(echo -e ${Y}"Start? (y/n): "${N})" ok
    [ "$ok" != "y" ] && { echo -e "${Y}Cancelled.${N}"; exit 0; }
}

# ------------------------------------------------------------
#  REJOIN HELPER
# ------------------------------------------------------------
do_rejoin() {
    local reason="$1"
    echo -e "${Y}[$(date +%H:%M:%S)] 🔄 Rejoining — $reason${N}"
    kill_roblox
    launch_roblox "$GAME_ID"
    sleep 8
}

# ------------------------------------------------------------
#  MAIN LOOP
# ------------------------------------------------------------
run_loop() {
    local rj_sec=$((REJOIN_MIN * 60))
    local sh_sec=$((SHOT_MIN * 60))
    local tick=0
    local next_shot=$sh_sec
    local next_rejoin=$rj_sec
    local cycle=1
    local miss_streak=0
    local last_status=""

    echo -e "${G}════════════════════════════════════════════════${N}"
    echo -e "${G}[+] Starting... Ctrl+C to stop.${N}"
    echo -e "${C}[i] Pumapasok sa game (ID: $GAME_ID)...${N}"
    echo -e "${G}════════════════════════════════════════════════${N}"

    kill_roblox
    launch_roblox "$GAME_ID"
    sleep 8

    send_webhook_text "$WEBHOOK" "🚀 **Auto-Rejoin started** — Game ID: \`$GAME_ID\`" "$MENTION"

    trap 'echo -e "\n${Y}[!] Stopped by user.${N}"; \
          send_webhook_text "$WEBHOOK" "🛑 **Auto-Rejoin stopped**" "n"; \
          exit 0' INT TERM

    while true; do
        sleep 1
        tick=$((tick + 1))

        # ---------- AUTO-DETECT ----------
        if is_playing; then
            miss_streak=0
        else
            miss_streak=$((miss_streak + 1))
            if [ $((miss_streak % 5)) -eq 0 ]; then
                echo -e "${Y}[$(date +%H:%M:%S)] ⚠ Not playing (${miss_streak}s / ${DETECT_SEC}s)${N}"
            fi

            if [ "$miss_streak" -ge "$DETECT_SEC" ]; then
                echo -e "${R}[$(date +%H:%M:%S)] ❌ Hindi na playing for ${DETECT_SEC}s — auto-rejoin!${N}"
                send_webhook_text "$WEBHOOK" "⚠️ **Auto-detect:** Hindi na playing si Roblox (\`${DETECT_SEC}s\`). Nag-re-rejoin na..." "n"
                do_rejoin "auto-detect"
                cycle=$((cycle + 1))
                tick=0; miss_streak=0
                next_rejoin=$rj_sec
                next_shot=$sh_sec
                continue
            fi
        fi

        # ---------- SCREENSHOT ----------
        if [ "$tick" -ge "$next_shot" ]; then
            echo -e "${B}[$(date +%H:%M:%S)] 📸 Screenshot (cycle #$cycle)...${N}"
            if take_screenshot; then
                if send_webhook "$WEBHOOK" "Cycle #$cycle — Game ID: \`$GAME_ID\`" "$MENTION" "3447003"; then
                    echo -e "${G}[$(date +%H:%M:%S)] ✅ Sent to Discord${N}"
                else
                    echo -e "${R}[$(date +%H:%M:%S)] ❌ Webhook failed${N}"
                fi
            else
                echo -e "${R}[$(date +%H:%M:%S)] ❌ Screenshot failed${N}"
            fi
            next_shot=$((next_shot + sh_sec))
        fi

        # ---------- SCHEDULED REJOIN ----------
        if [ "$tick" -ge "$next_rejoin" ]; then
            do_rejoin "scheduled (every ${REJOIN_MIN} min)"
            cycle=$((cycle + 1))
            tick=0; miss_streak=0
            next_rejoin=$rj_sec
            next_shot=$sh_sec
        fi
    done
}

# ------------------------------------------------------------
#  ENTRY POINT
# ------------------------------------------------------------
banner
check_deps
check_root
setup_menu
run_loop
