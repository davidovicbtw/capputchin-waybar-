<div align="center">

# ☕ capputchin-waybar

**A minimal, compact [Catppuccin Mocha](https://catppuccin.com) Waybar for Hyprland on Arch Linux.**

No giant pills, no blur, no gradients. Just small dark islands, a purple accent and the info you actually look at.

![preview](docs/preview.png)

<sub>Rendered at 1920×1200 @ 1.5× scaling. Media, Bluetooth, Wi-Fi and battery appear automatically when they're available.</sub>

![Arch](https://img.shields.io/badge/Arch-1793D1?style=flat-square&logo=archlinux&logoColor=white)
![Hyprland](https://img.shields.io/badge/Hyprland-58E1FF?style=flat-square&logo=hyprland&logoColor=black)
![Catppuccin](https://img.shields.io/badge/Catppuccin-Mocha-cba6f7?style=flat-square)

</div>

---

## Layout

```
┌──────────────────────────────────────────────────────────────────────────────────────┐
│ [] [1 2 3 4 5]          [󰥔 12:59  󰃭 03 Oct]       [󰏤 song] [󰕾 40% 󰤨 󰂯 󰁹 80%] [ 󰍛] [tray] │
└──────────────────────────────────────────────────────────────────────────────────────┘
   left                         center                              right
```

| Section | Modules | Interaction |
|---|---|---|
| **Left** | Arch logo · `hyprland/workspaces` | Click a workspace to switch to it. Active = mauve, empty = dimmed |
| **Center** | `clock` (time + date) | Hover shows the calendar, scroll changes the month, click opens `gnome-calendar` if installed |
| **Right** | `mpris` | Left click = play/pause · middle = previous · right = next. Hidden when nothing is playing |
| | `pulseaudio` | Scroll = ±5% · click = mixer (`pavucontrol` / `pwvucontrol`) · middle = mute (`wpctl` / `pactl`) |
| | `network` | Icon shows Wi-Fi signal / ethernet / disconnected · click = `nm-connection-editor`, `iwgtk` or `nmtui` |
| | `bluetooth` | Click = `blueman-manager` / `overskride` / `blueberry`. Hidden when there's no controller |
| | `battery` | Percentage + charging/plugged state, peach < 25%, red < 10%. Hidden on desktops |
| | `cpu` · `memory` | Small usage indicators |
| | `tray` | Normal system tray |

Everything uses **Waybar's built-in modules**. There are **no custom scripts** and no polling shell loops.

---

## Install

```bash
git clone https://github.com/davidovicbtw/capputchin-waybar-.git
cd capputchin-waybar-
./install.sh --dry-run   # inspect only: shows what it detected and the config it would write
./install.sh             # back up, install, validate, restart waybar
```

Options: `--dry-run` (writes nothing), `--no-restart` (installs, doesn't touch the running bar).

### Requirements

| Package | Needed for | Required? |
|---|---|---|
| `waybar` | everything | **yes** |
| `ttf-jetbrains-mono-nerd` (or any Nerd Font) | icons | **yes** |
| `playerctl` | `mpris` media module | optional |
| `pavucontrol` / `pwvucontrol` | volume click | optional |
| `networkmanager` (`nm-connection-editor`) | network click | optional |
| `bluez` + `blueman` | bluetooth module/click | optional |

```bash
sudo pacman -S --needed waybar ttf-jetbrains-mono-nerd playerctl pavucontrol
```

The installer **never installs packages** and never uses `sudo`. If something is missing, it adapts the config and tells you.

---

## What `install.sh` does

The script makes no assumptions about your system. It checks everything first:

1. **Waybar:** stops if `waybar` isn't installed.
2. **Hyprland:** checks `hyprctl` and whether you're inside a Hyprland session, and reports any `exec-once = waybar` lines in `~/.config/hypr` (read-only). It also warns if DMS/quickshell is referenced, because that bar would run next to Waybar.
3. **Tools:** checks which of `pavucontrol`, `pwvucontrol`, `wpctl`, `pactl`, `nm-connection-editor`, `iwgtk`, `nmtui`, `blueman-manager`, `overskride`, `blueberry`, `gnome-calendar`, `playerctl`, `bluetoothctl`, `nmcli` and a terminal actually exist.
4. **Adapts the config:** each click action uses the first tool found. If none is found, that `on-click` line is removed, so nothing ever calls a missing binary.
5. **Validates** the generated config as JSON (`python3` or `jq`) **before** writing anything.
6. **Backs up** the whole `~/.config/waybar` to `~/.config/waybar.bak-YYYYmmdd-HHMMSS`. It lists your old files and the modules your old config used, so you can re-add anything you miss.
7. **Installs** only `config.jsonc` and `style.css`. Other files (scripts, themes) are left alone. A legacy `config` file is renamed to `config.pre-capputchin`, because Waybar would otherwise load it instead of `config.jsonc`.
8. **Restarts Waybar safely:** it stops the running instance, starts a detached new one, then checks that it's alive and that its log has no errors. If Waybar fails to start, the script prints the exact command to restore your backup.

It **never** edits Hyprland or DMS configuration.

### Autostart

If the installer says no `exec-once` line was found, add this to your `~/.config/hypr/hyprland.conf` yourself:

```ini
exec-once = waybar
```

### Restore / uninstall

```bash
mv ~/.config/waybar ~/.config/waybar.capputchin
mv ~/.config/waybar.bak-YYYYmmdd-HHMMSS ~/.config/waybar
pkill -x waybar; hyprctl dispatch exec waybar
```

---

## Design notes

- **Palette:** Catppuccin Mocha. The bar is `crust` `#11111b`, islands are `base` `#1e1e2e`, text is `text`/`subtext0`, and the accent is `mauve` `#cba6f7`.
- **Size:** 30 px logical height (45 px physical at 1.5×), 13 px font, 8 px island radius, 3 px gaps. It fits 1280 px of logical width without crowding.
- **No** blur, transparency, gradients, shadows or borders (only a 1 px border on tooltips).
- **Workspaces:** 5 persistent workspaces so the layout doesn't jump. Remove `"persistent-workspaces"` in `config.jsonc` to show only the ones in use.
- `reload_style_on_change` is on, so CSS edits apply live.

## Customize

| Want to… | Edit |
|---|---|
| Change the accent | `@define-color mauve` in `style.css` (try `blue #89b4fa` or `pink #f5c2e7`) |
| Show the Wi-Fi name | `"format-wifi": "{icon} {essid}"` in `config.jsonc` |
| Hide CPU/RAM | remove `"group/system"` from `modules-right` |
| 12-hour clock | `"format": "󰥔 {:%I:%M %p  󰃭 %d %b}"` |
| Use a different font | `font-family` at the top of `style.css` |

## Files

```
.
├── install.sh            # safe detecting installer
├── waybar/
│   ├── config.jsonc      # → ~/.config/waybar/config.jsonc
│   └── style.css         # → ~/.config/waybar/style.css
└── docs/preview.png
```

## How it was tested

- `config.jsonc` validated as JSON; `install.sh` passes `bash -n` and `shellcheck` (only info-level notes left).
- The installer was run end to end in a sandboxed `$HOME` with stub commands, which exercised the backup, the legacy-`config` rename, tool fallbacks and click-action removal.
- The bar was rendered with real Waybar on a headless 1920×1200 @ 1.5× Wayland output to check CSS parsing, bar height and the clock format. It used `sway/workspaces` in place of `hyprland/workspaces` there, since the container has no Hyprland. That screenshot is the preview above.

---

<div align="center"><sub>Palette by <a href="https://github.com/catppuccin/catppuccin">Catppuccin</a> · icons by <a href="https://www.nerdfonts.com">Nerd Fonts</a></sub></div>
