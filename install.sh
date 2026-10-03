#!/usr/bin/env bash
# capputchin-waybar installer
#
# Safe by design:
#   - never uses sudo, never installs packages, never deletes files
#   - backs up ~/.config/waybar before writing anything
#   - only touches ~/.config/waybar/{config.jsonc,style.css,colors.css} (and
#     renames a conflicting legacy "config" file, which is also in the backup)
#   - if matugen is installed: adds one template + one [templates.*] block to
#     ~/.config/matugen (config.toml is backed up first, nothing is removed)
#   - never edits Hyprland or DMS configuration
#
# Usage: ./install.sh [--dry-run] [--no-restart] [--no-matugen]

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$REPO_DIR/waybar"
DEST_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/waybar"
HYPR_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
MT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/matugen"
MT_NAME="capputchin-waybar"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$DEST_DIR.bak-$STAMP"

DRY_RUN=0
RESTART=1
MATUGEN=1
for arg in "$@"; do
  case "$arg" in
    --dry-run)    DRY_RUN=1 ;;
    --no-restart) RESTART=0 ;;
    --no-matugen) MATUGEN=0 ;;
    -h|--help)    sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

c_ok=$'\e[32m'; c_warn=$'\e[33m'; c_err=$'\e[31m'; c_dim=$'\e[2m'; c_hl=$'\e[35m'; c_off=$'\e[0m'
step() { printf '\n%s==>%s %s\n' "$c_hl" "$c_off" "$*"; }
ok()   { printf '  %s✓%s %s\n' "$c_ok"   "$c_off" "$*"; }
warn() { printf '  %s!%s %s\n' "$c_warn" "$c_off" "$*"; }
err()  { printf '  %s✗%s %s\n' "$c_err"  "$c_off" "$*"; }
info() { printf '  %s·%s %s\n' "$c_dim"  "$c_off" "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------- 1. waybar
step "Checking Waybar"
if ! have waybar; then
  err "waybar is not installed. Install it yourself (e.g. 'sudo pacman -S waybar') and re-run."
  exit 1
fi
ok "waybar found: $(waybar --version 2>/dev/null | head -n1)"
[[ -f "$SRC_DIR/config.jsonc" && -f "$SRC_DIR/style.css" && -f "$SRC_DIR/colors.css" ]] || { err "repo files missing in $SRC_DIR"; exit 1; }

# ---------------------------------------------------------------- 2. hyprland
step "Checking Hyprland"
if have hyprctl; then
  ok "hyprctl found: $(hyprctl version 2>/dev/null | head -n1 || echo 'version unknown')"
else
  warn "hyprctl not found - hyprland/workspaces module will not work outside Hyprland"
fi
if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
  ok "running inside a Hyprland session"
else
  warn "HYPRLAND_INSTANCE_SIGNATURE is not set (not inside Hyprland right now?)"
fi
if [[ -d "$HYPR_DIR" ]]; then
  launch_lines="$(grep -rnE '^\s*exec(-once)?\s*=.*waybar' "$HYPR_DIR" 2>/dev/null || true)"
  if [[ -n "$launch_lines" ]]; then
    ok "Hyprland starts waybar (read-only check, not modified):"
    printf '%s\n' "$launch_lines" | sed 's/^/      /'
  else
    warn "no 'exec-once = waybar' found in $HYPR_DIR (left untouched; see README)"
  fi
  if grep -rqiE 'dms|dankmaterialshell|quickshell' "$HYPR_DIR" 2>/dev/null; then
    warn "DMS/quickshell references found - its own bar may run next to waybar (not modified)"
  fi
fi

# ---------------------------------------------------------------- 3. tools
step "Detecting optional tools"
TERMINAL=""
for t in kitty foot alacritty wezterm ghostty; do have "$t" && { TERMINAL="$t"; break; }; done

pick() { for c in "$@"; do have "${c%% *}" && { echo "$c"; return; }; done; echo ""; }
VOL_CLICK="$(pick pavucontrol pwvucontrol)"
MUTE_CLICK=""
have wpctl && MUTE_CLICK="wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
[[ -z "$MUTE_CLICK" ]] && have pactl && MUTE_CLICK="pactl set-sink-mute @DEFAULT_SINK@ toggle"
NET_CLICK="$(pick nm-connection-editor iwgtk)"
[[ -z "$NET_CLICK" && -n "$TERMINAL" ]] && have nmtui && NET_CLICK="$TERMINAL -e nmtui"
BT_CLICK="$(pick blueman-manager overskride blueberry)"
CAL_CLICK="$(pick gnome-calendar)"

report() { if [[ -n "$2" ]]; then ok "$1 → $2"; else warn "$1 → none found ($3)"; fi; }
report "volume click   " "$VOL_CLICK"  "click does nothing; scroll still changes volume"
report "mute (middle)  " "$MUTE_CLICK" "middle-click mute disabled"
report "network click  " "$NET_CLICK"  "click does nothing"
report "bluetooth click" "$BT_CLICK"   "click does nothing"
report "clock click    " "$CAL_CLICK"  "hover the clock for the built-in calendar"
if have playerctl; then ok "playerctl found (mpris media module)"
else warn "playerctl not found - the mpris module needs it (pacman -S playerctl); module will stay hidden"; fi
if have bluetoothctl; then ok "bluetoothctl found"; else info "bluetoothctl not found - bluetooth module hides itself without a controller"; fi
if have nmcli; then ok "nmcli found"; else info "nmcli not found - network module still works via kernel netlink"; fi
if compgen -G "/sys/class/power_supply/BAT*" >/dev/null; then ok "battery detected"; else info "no battery - battery module hides itself"; fi
if (( ! MATUGEN )); then info "matugen integration skipped (--no-matugen)"
elif have matugen; then ok "matugen found: $(matugen --version 2>/dev/null | head -n1) - wallpaper colours will be wired up"
else info "matugen not found - using the static Catppuccin Mocha palette"; MATUGEN=0; fi

# ---------------------------------------------------------------- 4. build config
step "Building config for this system"
# Replace a default on-click command with the detected one, or drop the line.
adapt() {  # $1 = default command in repo config, $2 = replacement (may be empty)
  if [[ -z "$2" ]]; then
    CONFIG="$(printf '%s\n' "$CONFIG" | grep -vF "\"$1\"")"
  else
    local pat="\"$1\"" rep="\"$2\""
    CONFIG="${CONFIG//"$pat"/"$rep"}"
  fi
}
CONFIG="$(<"$SRC_DIR/config.jsonc")"
adapt "pavucontrol"                                 "$VOL_CLICK"
adapt "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"  "$MUTE_CLICK"
adapt "nm-connection-editor"                        "$NET_CLICK"
adapt "blueman-manager"                             "$BT_CLICK"
adapt "gnome-calendar"                              "$CAL_CLICK"

TMP="$(mktemp -d)"; trap 'rm -r "$TMP"' EXIT
printf '%s\n' "$CONFIG" > "$TMP/config.jsonc"

# Validate (strip full-line // comments, then parse as JSON)
if have python3; then
  grep -vE '^\s*//' "$TMP/config.jsonc" | python3 -m json.tool >/dev/null \
    && ok "config.jsonc is valid JSON" || { err "generated config is invalid - nothing written"; exit 1; }
elif have jq; then
  grep -vE '^\s*//' "$TMP/config.jsonc" | jq empty \
    && ok "config.jsonc is valid JSON" || { err "generated config is invalid - nothing written"; exit 1; }
else
  warn "neither python3 nor jq found - skipping JSON validation"
fi

if (( DRY_RUN )); then
  step "Dry run - generated config:"
  cat "$TMP/config.jsonc"
  exit 0
fi

# ---------------------------------------------------------------- 5. backup + install
step "Installing"
if [[ -e "$DEST_DIR" ]]; then
  info "existing files in $DEST_DIR:"
  ls -la "$DEST_DIR" | sed 's/^/      /'
  for f in config config.jsonc; do
    [[ -f "$DEST_DIR/$f" ]] || continue
    mods="$(grep -oE '"(modules-(left|center|right))"\s*:\s*\[[^]]*\]' "$DEST_DIR/$f" | tr -s ' ' || true)"
    [[ -n "$mods" ]] && { info "modules in your old $f (re-add any you miss):"; printf '%s\n' "$mods" | sed 's/^/      /'; }
  done
  cp -a "$DEST_DIR" "$BACKUP_DIR"
  ok "backup created: $BACKUP_DIR"
else
  mkdir -p "$DEST_DIR"
fi

# Waybar prefers a file named "config" over "config.jsonc" in the same dir.
if [[ -f "$DEST_DIR/config" ]]; then
  mv "$DEST_DIR/config" "$DEST_DIR/config.pre-capputchin"
  ok "renamed old 'config' → config.pre-capputchin (also in backup)"
fi

install -m 644 "$TMP/config.jsonc"     "$DEST_DIR/config.jsonc"
install -m 644 "$SRC_DIR/style.css"    "$DEST_DIR/style.css"
ok "wrote $DEST_DIR/config.jsonc"
ok "wrote $DEST_DIR/style.css"
# Keep an existing capputchin colors.css (it may hold matugen wallpaper colours);
# anything else named colors.css is replaced (it is in the backup).
if [[ -f "$DEST_DIR/colors.css" ]] && grep -q 'capputchin-waybar colors' "$DEST_DIR/colors.css"; then
  ok "kept existing $DEST_DIR/colors.css"
else
  install -m 644 "$SRC_DIR/colors.css" "$DEST_DIR/colors.css"
  ok "wrote $DEST_DIR/colors.css (Catppuccin Mocha)"
fi
info "other files in $DEST_DIR (scripts, themes, …) were left as they are"

# ---------------------------------------------------------------- 6. matugen
if (( MATUGEN )); then
  step "Wiring up matugen"
  MT_TEMPLATE="$MT_DIR/templates/$MT_NAME.css"
  MT_CONFIG="$MT_DIR/config.toml"
  mkdir -p "$MT_DIR/templates"
  if [[ -f "$MT_TEMPLATE" ]] && ! cmp -s "$REPO_DIR/matugen/$MT_NAME.css" "$MT_TEMPLATE"; then
    cp -a "$MT_TEMPLATE" "$MT_TEMPLATE.bak-$STAMP"
    ok "backup created: $MT_TEMPLATE.bak-$STAMP"
  fi
  install -m 644 "$REPO_DIR/matugen/$MT_NAME.css" "$MT_TEMPLATE"
  ok "wrote $MT_TEMPLATE"

  if [[ -f "$MT_CONFIG" ]] && grep -qF "[templates.$MT_NAME]" "$MT_CONFIG"; then
    ok "$MT_CONFIG already has [templates.$MT_NAME] (left as is)"
  else
    if [[ -f "$MT_CONFIG" ]]; then
      cp -a "$MT_CONFIG" "$MT_CONFIG.bak-$STAMP"
      ok "backup created: $MT_CONFIG.bak-$STAMP"
    else
      printf '[config]\n' > "$MT_CONFIG"
    fi
    cat >> "$MT_CONFIG" <<EOF

# added by capputchin-waybar install.sh
[templates.$MT_NAME]
input_path = "$MT_TEMPLATE"
output_path = "$DEST_DIR/colors.css"
post_hook = "pkill -SIGUSR2 -x waybar || true"
EOF
    ok "added [templates.$MT_NAME] to $MT_CONFIG"
  fi
  if grep -rqiE 'dms|dankmaterialshell' "$HYPR_DIR" 2>/dev/null; then
    warn "DMS detected: if DMS runs matugen for you, make sure it also runs your user matugen templates"
  fi
  info "apply wallpaper colours with:  matugen image /path/to/wallpaper.png --prefer saturation"
fi

# ---------------------------------------------------------------- 7. restart
(( RESTART )) || { step "Done (restart skipped). Run: pkill -x waybar; waybar &"; exit 0; }
if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
  warn "no WAYLAND_DISPLAY - not restarting. Waybar will pick up the config on next login."
  exit 0
fi

step "Restarting Waybar"
if pgrep -x waybar >/dev/null; then
  pkill -x waybar || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x waybar >/dev/null || break; sleep 0.3; done
  ok "stopped running waybar"
fi
LOG="${XDG_RUNTIME_DIR:-/tmp}/capputchin-waybar.log"
setsid -f waybar >"$LOG" 2>&1 </dev/null
sleep 2
if pgrep -x waybar >/dev/null; then
  ok "waybar is running (log: $LOG)"
  if grep -qiE '\[(error|critical)\]' "$LOG"; then
    warn "waybar reported errors:"
    grep -iE '\[(error|critical|warning)\]' "$LOG" | sed 's/^/      /'
  else
    ok "no errors in waybar log"
  fi
else
  err "waybar exited. Log:"
  sed 's/^/      /' "$LOG"
  [[ -d "$BACKUP_DIR" ]] && err "restore with: mv '$DEST_DIR' '$DEST_DIR.failed-$STAMP' && mv '$BACKUP_DIR' '$DEST_DIR'"
  exit 1
fi

step "Done ✨"
